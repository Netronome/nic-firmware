BEGIN{ 
    print "/* This file is generated during build. Do not edit! */"
    print "__export __shared __emem ext_stats_key_t ext_stats_phy_keys[] = {" 
}
!/$^[[:space:]]*$/{ print "\"" $1 "\"," }
END{ print "};" }
