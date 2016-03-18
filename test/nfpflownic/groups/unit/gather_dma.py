#
# Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
#
"""
Unit test classes for the NFPFlowNIC Software Group.
"""

import os
import re
import hashlib
import ntpath
import random
from tempfile import mkstemp
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.utilities import timed_poll
from netro.testinfra import Test, LOG_sec, LOG, LOG_endsec
from netro.testinfra.nti_exceptions import NtiGeneralError


class NFPFlowNICGatherDMA(Test):
    """The tests in this file share a lot of common code which is kept
    in this class"""

    # Information applicable to all subclasses
    _gen_info = """

    """

    def __init__(self, src, dst, group=None, name="", summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        Test.__init__(self, group, name, summary)

        self.src = None
        self.src_intf = None
        self.dut = None
        self.dut_intf = None

        if src[0]:
            self.src = src[0]
            self.src_intf = src[2]
            self.dst = dst[0]
            self.dst_intf = dst[2]

        # These will be set in the run() method
        self.dst_ip = None
        self.hash = None
        self.tx_gather_count = None
        self.tmp_src_dir = None
        self.tmp_dst_dir = None
        self.tmp_file = None

        return

    def run(self):
        """Run the test
        @return:  A result object"""

        # Refresh intf objects.
        self.src.refresh()
        self.dst.refresh()

        # Get address.
        dst_if = self.dst.netifs[self.dst_intf]
        self.dst_ip = dst_if.ip

        # If scatter-gather is off, attempt to turn it on.
        if not self.check_scatter_gather(self.src, self.src_intf, "on"):
            try:
                cmd = 'ethtool -K %s sg on' % self.src_intf
                self.src.cmd(cmd)

                # Verify scatter-gather has been turned on.
                if not self.check_scatter_gather(self.src,
                                                 self.src_intf, "on"):
                    raise
            except:
                raise NtiGeneralError("Unable to enable scatter-gather on %s!"
                                      % self.src_intf)

        # Loop:
        #  Generate the appropriately sized file.
        #  SCP the file from the dut to the endpoint.
        #  Verify the tx_gather counters have incremented.
        #  Using md5hash and cmp, verify the files are the same on both ends.
        self.tmp_src_dir = self.src.make_temp_dir()
        self.tmp_dst_dir = self.dst.make_temp_dir()
        tmp_file_list = []
        try:
            buf_size = 0
            mb = 1024 * 1024  # One megabyte.
            # Iterate over 1/2 MB, 1 MB and 2 MB file sizes.
            for file_size in [mb/2, mb, mb*2]:
                _, self.tmp_file = mkstemp()
                tmp_file_list.append(self.tmp_file)
                with open(self.tmp_file, 'w', buf_size) as f:
                    while os.stat(self.tmp_file).st_size < file_size:
                        f.write(str(random.random()) + '\n')

                # Using md5, obtain hash.
                md5hash = hashlib.md5()
                with open(self.tmp_file) as f:
                    for line in f:
                        md5hash.update(line)
                self.hash = md5hash.hexdigest()

                # Copy tmp file to dut.
                self.src.cp_to(self.tmp_file, self.tmp_src_dir)

                before_gather_count, after_gather_count = \
                    self.scp_file_and_get_tx_counter()

                if before_gather_count >= after_gather_count:
                    comment = ("Error: tx_gather counter did not increment "
                               "(before: %s) (after: %s)!" %
                               (before_gather_count, after_gather_count))
                    return NrtResult(name=self.name,
                                     testtype=self.__class__.__name__,
                                     passed=False, comment=comment)

                # Take md5 hash of destination file and compare with local.
                cmd = ("python -c \"import sys; import hashlib; "
                       "md5hash = hashlib.md5(); "
                       "[md5hash.update(line) for line in sys.stdin]; "
                       "print md5hash.hexdigest()\" < %s" %
                       os.path.join(self.tmp_dst_dir,
                                    ntpath.basename(self.tmp_file)))

                _, dst_hash = self.dst.cmd(cmd)
                dst_hash = dst_hash.strip('\n')

                if cmp(self.hash, dst_hash):
                    comment = ("Hashes (local hash: %s) (dst_hash: %s) are "
                               "different!" % (self.hash, dst_hash))
                    return NrtResult(name=self.name,
                                     testtype=self.__class__.__name__,
                                     passed=False, comment=comment)

            # Just send the last file created with scatter-gather turned off
            # and verify the tx_gather counter does not increment.
            # Turn scatter-gather off.
            cmd = 'ethtool -K %s sg off' % self.src_intf
            self.src.cmd(cmd)

            # Verify scatter-gather has been turned off.
            if not self.check_scatter_gather(self.src, self.src_intf, "off"):
                raise NtiGeneralError("Unable to turn off scatter-gather on "
                                      "%s!" % self.src_intf)

            # Remove the original file from the endpoint.
            cmd = ('rm %s' % os.path.join(self.tmp_dst_dir,
                                          ntpath.basename(self.tmp_file)))
            self.dst.cmd(cmd)

            # Verify it was removed.
            timed_poll(30, self.not_exists_host, self.dst,
                       os.path.join(self.tmp_dst_dir,
                                    ntpath.basename(self.tmp_file)),
                       delay=1)

            before_gather_count, after_gather_count = \
                self.scp_file_and_get_tx_counter()

            if before_gather_count != after_gather_count:
                comment = ("Error: tx_gather counter incremented "
                           "(before: %s) (after: %s)!" % (before_gather_count,
                                                          after_gather_count))
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False, comment=comment)

        finally:
            # Always make sure we turn scatter-gather back on.
            cmd = 'ethtool -K %s sg on' % self.src_intf
            self.src.cmd(cmd)

            # Remove all tmp created files.
            LOG_sec("Cleaning up tmp directories on remote hosts.")
            self.src.rm_dir(self.tmp_src_dir)
            self.dst.rm_dir(self.tmp_dst_dir)
            LOG_endsec()

            LOG_sec("Cleaning up local tmp files.")
            for tmp in tmp_file_list:
                if os.path.isfile(tmp):
                    os.remove(tmp)
            LOG_endsec()

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True, comment="")

    def scp_file_and_get_tx_counter(self):
        """
        Get the tx_counter before we scp the file, then scp the file, verify
        it was sent and then get the tx_counter after, returning both
        counter values.

        :return: Before and After tx_gather counter values.
        """
        # Grab the before tx_counter value on dut.
        before_gather_count = self.get_tx_counter(self.src, self.src_intf)

        # scp file from dut to endpoint.
        cmd = ('scp %s root@%s:%s' %
               (os.path.join(self.tmp_src_dir, ntpath.basename(self.tmp_file)),
                self.dst_ip, self.tmp_dst_dir))
        self.src.cmd(cmd)

        # Verify it was sent, then check the counter.
        timed_poll(30, self.dst.exists_host,
                   os.path.join(self.tmp_dst_dir,
                                ntpath.basename(self.tmp_file)),
                   delay=1)

        # Grab the after tx_counter value on dut.
        after_gather_count = self.get_tx_counter(self.src,
                                                 self.src_intf)

        return before_gather_count, after_gather_count

    def show_offload(self, host, intf):
        """
        Simply run "ethtool -k" on an interface.

        :param host: Host to check against.
        :param intf: Interface to show offload of.
        :return: return value and stdout
        """
        cmd = "ethtool -k %s" % intf
        ret, out = host.cmd(cmd)
        return ret, out

    def check_scatter_gather(self, host, intf, state=None):
        """
        Check if scatter gather is on/off, depending on input.

        :param host: Host to check against.
        :param intf: Interface to show offload of.
        :param state: State to check for scatter gather flag: on/off.
        :return: True if state matches the requested input, False otherwise.
        """
        _, out = self.show_offload(host, intf)
        match = re.search(r'scatter-gather:\s([a-z]+)', out)

        # If scatter-gather flag matches the state requested, return True,
        # otherwise, return False.
        if match.group(1) == state:
            return True

        return False

    def show_stats(self, host, intf):
        """
        Run "ethtool -S" on an interface.

        :param host: Host to check against.
        :param intf: Interface to show offload of.
        :return: return value and stdout
        """
        cmd = "ethtool -S %s" % intf
        ret, out = host.cmd(cmd)
        return ret, out

    def get_tx_counter(self, host, intf):
        """
        Get the current value of the tx_gather counter.

        :param host: Host to check against.
        :param intf: Interface to check counter on.
        :return: return value and stdout
        """
        _, out = self.show_stats(host, intf)
        match = re.search(r'tx_gather:\s([0-9]+)', out)
        return int(match.group(1))

    def not_exists_host(self, host, file_name):
        """
        Return inverse of exists_host.

        :param host: Host to check against.
        :param file_name: File name to check for.
        :return: True if file does not exist, False otherwise.
        """
        return not host.exists_host(file_name)
