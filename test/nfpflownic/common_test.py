##
## Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
##

from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.nti_exceptions import NtiGeneralError
from netro.testinfra.test import Test

###############################################################################
# Test with cleanup
###############################################################################
class CommonTest(Test):
    """A generic test class. Tests are subclasses of this class and
    actual tests are instances of those sub classes.

    This class provides more structure than Test class, the prepare
    execute and cleanup stages are separate.  The execute stage is
    expected to throw exceptions when things fail.  Those exceptions
    will be propagated but cleanup stage will always follow.

    This class also contains the common initialization.
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
        self.src_ifn = None
        self.dst = None
        self.dst_ifn = None

        # src and dst maybe None if called without config file for list
        if not src[0]:
            return

        self.src = src[0]
        self.src_addr = src[1]
        self.src_ifn = src[2]
        self.src_if = self.src.netifs[self.src_ifn]
        self.src_addr_v6 = src[3]

        self.dst = dst[0]
        self.dst_addr = dst[1]
        self.dst_ifn = dst[2]
        self.dst_if = self.dst.netifs[self.dst_ifn]
        self.dst_addr_v6 = dst[3]
        return

    def prepare(self):
        """
        Prepare tests

        @return NrtResult on error
        """
        pass

    def execute(self):
        """
        Run the test, throw an exception if anything goes wrong
        """
        pass

    def cleanup(self):
        """
        Cleanup after tests
        """
        pass

    def run(self):
        res = self.prepare()
        if res:
            return res

        try:
            self.execute()
        finally:
            self.cleanup()

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True)


    def ping(self, count=10, size=0, pattern="", fail=True):
        opts = ""
        if size:
            opts = opts + "-s %d " % (size)
        if pattern:
            opts = opts + "-p %s " % (pattern)

        _, out = self.src.cmd('ping -c %d -i0.05 -W2 %s -I %s %s' %
                               (count, opts, self.src_ifn,
                                self.dst_addr[:-3]), fail=False)
        if _ and fail:
            raise NtiGeneralError("Couldn't ping endpoint")
        if _ == 0 and not fail:
            raise NtiGeneralError("Could ping endpoint")


    def ping6(self, count=10, fail=True):
        _, out = self.src.cmd('ping6 -c %d -i0.1 -W5 -I %s %s' %
                               (count, self.src_ifn,
                                self.dst_addr_v6[:-3]), fail=False)
        if _ and fail:
            raise NtiGeneralError("Couldn't ping6 endpoint")
        if _ == 0 and not fail:
            raise NtiGeneralError("Could ping6 endpoint")


    def tcpping(self, count=10, sport=100, dport=58, fail=True):
        _, out = self.src.cmd('hping3 %s --fast -c %d -s %d -p %d -d 50 -k --syn' %
                               (self.dst_addr[:-3], count, sport, dport), fail=False)
        if _ and fail:
            return NtiGeneralError("Couldn't TCP ping endpoint")
        if _ == 0 and not fail:
            raise NtiGeneralError("Could TCP ping endpoint")
