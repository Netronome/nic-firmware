##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##

"""Test groups of NFPFlowNIC"""

import collections
import netro.testinfra
from nfpflownic import *
from netro.testinfra.nrt_result import NrtResult
from netro.db_schemas import test_suite_info
from netro.db_schemas import dblib
from netro.testinfra import test
from ConfigParser import ConfigParser

class Project(netro.testinfra.Project):
    """Tests for nfpflownic."""

    summary = "Tests for NFPFlowNIC with kernel firmware loading"
    _groups = collections.OrderedDict((("setup", NFPFlowNICSetup),
                                       ("unit", NFPFlowNICUnit),
                                       ("perf",
                                        NFPFlowNICPerfTest)))

    def _init(self):
        """
        Initialise DB before all group inits are done.

        """
        # Result object to be filled in later.
        test.Project.ResultClass = NrtResult

        # If a database config was provided, read in the config file, grab an
        # instance to the singleton TestSuiteInfo and update params so the
        # database schema can use it.
        test_info_obj = test_suite_info.TestInfoData()
        if test_info_obj.data:
            # Assign appropriate parameters from the TestInfoData (params
            # which came from the command line of ticmd).
            db_cfg_file = test_info_obj.data[0]
            log_to_db = test_info_obj.data[1]
            dut = test_info_obj.data[2]

            # Read in the ConfigParser-style configuration.
            cfg = ConfigParser()
            cfg.readfp(db_cfg_file)

            # Assign database config parameters.
            section = 'TestSuiteCfg'
            test_info = test_suite_info.TestSuiteInfo()
            test_info.username = cfg.get(section, 'username')
            test_info.password = cfg.get(section, 'password')
            test_info.dbserver = cfg.get(section, 'dbserver')
            test_info.dbname = cfg.get(section, 'dbname')
            test_info.nfm_line = log_to_db[0]
            test_info.nfm_build = int(log_to_db[1])
            test_info.nfm_revision = log_to_db[2]
            test_info.dut = dut

            # Update DbApp class with the latest URI from the config file.
            dblib.DbApp().update_dbapp_uri()

