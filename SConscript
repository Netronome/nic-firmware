import subprocess
import os

Import('env')
env.Export('env')
SConscript('SConscript.clean')

# Default PATHs
default_path = [ \
'/usr/local/sbin', \
'/usr/local/bin', \
'/usr/sbin', \
'/usr/bin', \
'/sbin', \
'/bin', \
'/opt/netronome/bin', \
]

env['ENV']['PATH'] = default_path

env_path=env.Dir("#").abspath
script_cwd=env.Dir(".").srcnode().abspath
print "ENV: " + env_path
print "SCP: " + script_cwd

env['ENV']['ROOT_ENV_PATH'] = env_path
env['ENV']['TOP_SCRIPT_PATH'] = script_cwd

def add_kmod(env, kmod):
    enable_kmod_build = True
    add_depends = False
    tgt_dir = kmod.split('.')[0]
    kmod_build_cmd = 'cd ' + env['ENV']['TOP_SCRIPT_PATH'] + ' && cd kernel/' + tgt_dir + ' && '
    if GetOption('kernel-dir'):
        kmod_build_cmd += 'KERNELDIR=' + GetOption('kernel-dir') + ' make'
    else:
        kmod_build_cmd += 'make'

    if GetOption('pbuild'):
        kmod_build_cmd += ' -j ' + str(GetOption('pbuild'))

    kmod_clean_cmd = 'cd ' + env['ENV']['TOP_SCRIPT_PATH'] + ' && cd kernel/' + tgt_dir + ' && make clean'

    if enable_kmod_build:
        kmod_fqn = (env['ENV']['TOP_SCRIPT_PATH'] + '/kernel/' + tgt_dir + '/' + kmod)
        kmod_build = env.Command(kmod_fqn, None, kmod_build_cmd)
        env.AlwaysBuild(kmod_build)
        Default(kmod_build)
        env.Precious(kmod_build)
        env.CleanAction(kmod_build, Action([kmod_clean_cmd]))
        if add_depends:
            print '    Adding kmod dep of Netro Build'
            env.Depends(kmod_build, env['NETRO_BUILD'])


def add_firmware(env, firmware):
# run from top level of repo, give firmware/*.cat target
    print firmware
    fw_build_cmd = 'cd ' + env['ENV']['TOP_SCRIPT_PATH'] + ' && '
    if GetOption('PLATFORM'):
        fw_build_cmd += 'PLATFORM=' + GetOption('PLATFORM') + ' make ' + firmware
    else:
        fw_build_cmd += 'make ' + firmware

    if GetOption('pbuild'):
        fw_build_cmd += ' -j ' + str(GetOption('pbuild'))

    fw_clean_cmd = 'cd ' + env['ENV']['TOP_SCRIPT_PATH'] + ' && make clean'  # TODO individual clean targets
    firmware_build = env.Command((env['ENV']['TOP_SCRIPT_PATH'] + '/firmware/cat/' + firmware), None, fw_build_cmd)
    env.AlwaysBuild(firmware_build)
    env.Precious(firmware_build)
    Default(firmware_build)
    env.CleanAction(firmware_build, Action(fw_clean_cmd))
    #load_make_target = ('make load_' + firmware.split()[0])

def default_program(env, *args, **kwargs):
    # Add program as a default
    target = env.Program(*args, **kwargs)
    Default(target)

# Create Markdown Docs Builder
def markdown_builder(target, source, env):
    doc_cmd = "cd " + env['DOC_PATH'] + " && pandoc"
    if 'PANDOC_ARGS' in env.Dictionary():
        doc_cmd += " " + env['PANDOC_ARGS']
    for s in source:
        doc_cmd += " " + str(s.name)
    doc_cmd += " -o"
    for t in target:
        doc_cmd += " " + str(t.name)
    subprocess.check_call([doc_cmd], shell=True)

# define builder
md_bld = Builder(action = markdown_builder)

# Add Markdown Docs Builder to env
env.Append(BUILDERS = {'MarkdownBuilder': md_bld})

# Create Graphviz Docs Builder
def graphviz_builder(target, source, env):
    from SCons.Errors import BuildError, UserError

    if (len(target) != 1 or len(source) != 1):
        raise UserError("Only one source, target supported for GraphvizBuilder")

    t = str(target[0])
    s = str(source[0])

    try:
        graphviz_tag_tool = os.path.join(env['DOC_PATH'], 'graphviz')
        graphviz_program = \
            subprocess.check_output([graphviz_tag_tool, s]).rstrip()

        cmd = [graphviz_program, '-T' + env['OUTPUT_FORMAT'], '-o' + t, s]
        subprocess.check_call(cmd)

    except subprocess.CalledProcessError as e:
        raise BuildError(errstr=str(e))

# define builder
graphviz_bld = Builder(action = graphviz_builder)

# Add Graphviz Docs Builder to env
env.Append(BUILDERS = {'GraphvizBuilder': graphviz_bld})

# Modify the Env
# Define Flowenv paths
env['ENV']['ROOT_ENV_PATH'] = env_path
env['ENV']['TOP_SCRIPT_PATH'] = script_cwd

env['ENV']['FLOWENV_PATH'] = script_cwd + '/deps/flowenv.hg'

env['ENV']['FLOWENV_INC_PATH'] = [ \
    (env['ENV']['FLOWENV_PATH'] + '/user/libs/flowenv'), \
    (env['ENV']['FLOWENV_PATH'] + '/me/lib'), \
]

env['ENV']['FLOWENV_LIB_PATH'] = [ \
    (env['ENV']['FLOWENV_PATH'] + '/user/libs/flowenv'), \
    (env['ENV']['FLOWENV_PATH'] + '/me/lib') \
]


# Define Netronome BSP paths
env['ENV']['NETRONOME_DIR'] = '/opt/netronome'
env['ENV']['BSP_RELEASE_INC_PATH'] = (env['ENV']['NETRONOME_DIR'] + '/include')
env['ENV']['BSP_RELEASE_LIB_PATH'] = (env['ENV']['NETRONOME_DIR'] + '/lib')

# Define common
env['ENV']['COM_INC_PATH'] = [ \
    ('./'), \
    env['ENV']['BSP_RELEASE_INC_PATH'], \
    (script_cwd + '/include'), \
    (script_cwd + '/src/lib/vr'), \
    (script_cwd + '/src/lib/nfp_vr_health'), \
]

env['ENV']['COM_LIB_PATH'] = [ \
    env['ENV']['BSP_RELEASE_LIB_PATH'], \
    '/usr/local/lib', \
    '/usr/lib/x86_64-linux-gnu/', \
    '/lib/x86_64-linux-gnu/', \
    (script_cwd + '/src/lib/vr'), \
    (script_cwd + '/src/lib/nfp_vr_health'), \
]

env['ENV']['COM_LIBS']  = ['nfp']



# Add funcs to env
env.AddMethod(add_kmod,'AddKmod')
env.AddMethod(add_firmware, 'AddFirmware')
env.AddMethod(default_program, 'DefaultProgram')

# Set the default to nothing, we will build it later
Default(None)

# Find docs folders to build
docs_sub_dirs = []
for d in os.walk(script_cwd + '/docs').next()[1]:
    docs_sub_dirs.append(script_cwd + '/docs/' + d)

# Include SConscript files in docs dirs
SConscript(dirs=docs_sub_dirs, exports='env')

# Generate Firmware targets
found_firmware_build_targets = False
found_firmware_load_targets = False
found_firmware_global_commands = False

#pull in deps for firmware and host code
print "Fetching deps"
subprocess.check_call(['make firmware_fetch_deps'], shell=True)

output = subprocess.check_output(['make firmware_help'], shell=True)
for line in output.split('\n'):
    line = line.strip(' \t\n\r')

    # Build targets
    if found_firmware_build_targets:
        if line.endswith('.cat'):
            print 'Adding firmware to build:', line
            env.AddFirmware(line)
        else:
            found_firmware_build_targets = False

    # Load targets
    if found_firmware_load_targets:
        if line.startswith('load_'):
            print 'TODO - Adding firmware load target:', line
            # TODO
        else:
            found_firmware_load_targets = False

    # Global firmware targets
    if found_firmware_global_commands:
        if line.startswith('firmware_'):
            mod_line = line.split('--')[0].strip(' \t\n\r')
            mod_line = mod_line.split('_', 1)[-1]
            print 'TODO - Found firmware global command:', mod_line
            #global_cmd = env.Command(('firmware/' + mod_line), \
            #    None, ('make firmware_' + mod_line))
        else:
            found_firmware_global_commands = False

    # Section Detection
    if 'Firmware build targets' in line:
        found_firmware_build_targets = True
    if 'Firmware load targets' in line:
        found_firmware_load_targets = True
    if 'Global commands' in line:
        found_firmware_global_commands = True

# vim: set expandtab shiftwidth=4:
