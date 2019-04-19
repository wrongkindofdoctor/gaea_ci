#!/usr/bin/env python
import collections
import errno
import os
import shlex
import subprocess
import sys  # Testing


DOC_LAYOUT = 'MOM_parameter_doc.layout'
verbose = False


def regressions():
    base_path = os.getcwd()
    regressions_path = os.path.join(base_path, 'regressions')
    regression_tests = get_regression_tests(regressions_path)

    # Check output
    if (verbose):
        for compiler in regression_tests:
            print('{}: ['.format(compiler))
            for config in regression_tests[compiler]:
                print("    '{}:',".format(config))
                for reg, test in regression_tests[compiler][config]:
                    print('        {}'.format(reg))
                    #print('        {}'.format(test))
            print(']')

    n_tests = sum(len(t) for t in regression_tests['gnu'].values())
    print('Number of tests: {}'.format(n_tests))

    # Temporarily dump output to /dev/null
    f_null = open(os.devnull, 'w')

    # Switching compilers will currently clobber the old result!
    # Maybe just do one at a time?
    for compiler in regression_tests:
        for config in regression_tests[compiler]:
            for reg_path, test_path in regression_tests[compiler][config]:
                layout_path = os.path.join(test_path, DOC_LAYOUT)
                params = parse_mom6_param(layout_path)

                ni = int(params['NIPROC'])
                nj = int(params['NJPROC'])
                nprocs = ni * nj

                # TODO: repro, [no]symmetric, etc
                exe_path = os.path.join(base_path, 'build', compiler, config,
                                        'repro', 'MOM6')

                # For now just test 1-node jobs
                if nprocs <= 32:
                    # FMS requires that RESTART be created
                    os.chdir(test_path)
                    mkdir_p('RESTART')

                    srun_flags = ' '.join([
                        '--exclusive',
                        '-n {}'.format(nprocs),
                    ])

                    cmd = '{launcher} {flags} {exe}'.format(
                        launcher='srun',
                        flags=srun_flags,
                        exe=exe_path
                    )
                    print(test_path)
                    print(cmd)

                    #print('Running {}...'.format(os.path.basename(test_path)))
                    #proc = subprocess.Popen(
                    #    shlex.split(cmd),
                    #    stdout=f_null,
                    #    stderr=f_null,
                    #)
                    #print(proc.pid)

    f_null.close()


def get_regression_tests(reg_path, test_dirname='MOM6-examples'):
    regression_tests = {}

    model_configs = os.listdir(reg_path)
    for config in model_configs:
        config_path = os.path.join(reg_path, config)
        for path, _, files in os.walk(config_path):
            # TODO: symmetric and static support
            compilers = tuple(
                os.path.splitext(f)[1].lstrip('.')
                for f in files if f.startswith('ocean.stats')
            )
            if compilers:
                reg_dirname = os.path.basename(reg_path.rstrip(os.sep))
                r_s = path.index(reg_dirname)
                r_e = r_s + len(reg_dirname)
                test_path = path[:r_s] + test_dirname + path[r_e:]

                # Old format
                #regression_tests[config].append((path, test_path, compilers))
                for compiler in compilers:
                    if not compiler in regression_tests:
                        regression_tests[compiler] = collections.defaultdict(list)

                    test_record = path, test_path
                    regression_tests[compiler][config].append(test_record)

    return regression_tests


def parse_mom6_param(path):
    params = {}
    with open(path) as param_file:
        for line in param_file:
            param_stmt = line.split('!')[0].strip()
            if param_stmt:
                key, val = [s.strip() for s in param_stmt.split('=')]
                params[key] = val
    return params


def mkdir_p(path):
    try:
        os.makedirs(path)
    except EnvironmentError as exc:
        if exc.errno != errno.EEXIST:
            raise


if __name__ == '__main__':
    regressions()
