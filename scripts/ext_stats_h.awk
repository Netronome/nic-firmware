BEGIN{ COUNT=0 }
!/^[[:space:]]*$/{ 
    if (length($0) > 30) { 
        print $0 " is too long"
        exit 1
    }
    DATA[COUNT++] = $0
}
END{
    x = log(COUNT) / log(2)
    x = 8 * 2 ** ((x == int(x)) ? x : int(x) + 1)
    print "/* This file is generated during build. Do not edit! */"
    for (i = 0; i < COUNT; ++i) { printf("#define EXT_STATS_%s 0x%x\n", toupper(DATA[i]), i*8) }
    print "#define EXT_STATS_SIZE " x 
    print "#if defined(__NFP_LANG_MICROC)"
    print "typedef struct {"
    print "\tunion {"
    print "\t\tstruct {"
    for (i = 0; i < COUNT; ++i) { print "\t\t\tunsigned long long " DATA[i] ";" }
    print "\t\t};"
    print "\t\tuint64_t __raw[" (x / 8) "];"
    print "\t};"
    print "} ext_stats_t;"
    print "#endif"
}
