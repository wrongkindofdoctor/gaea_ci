#!/usr/bin/env python
import collections
import errno
import os
import shlex
import subprocess

import sys
verbose = True

DOC_LAYOUT = 'MOM_parameter_doc.layout'


compilers = [
    'gnu',
    'intel',
    'pgi',
]


# TODO: Generate from regressions?
model_drivers = [
    'ocean_only',
    'ice_ocean_SIS',
    'ice_ocean_SIS2',
    'coupled_AM2_LM3_SIS',
    'coupled_AM2_LM3_SIS2',
    'land_ice_ocean_LM3_SIS2',
]


def get_regression_tests(reg_path):
    regression_tests = collections.defaultdict(list)

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
                # Replace 'regressions' with 'MOM6-examples'
                r_s = path.index('regressions')
                r_e = r_s + len('regressions')
                test_path = path[:r_s] + 'MOM6-examples' + path[r_e:]

                regression_tests[config].append((path, test_path, compilers))

    return regression_tests

def regressions():
    base_path = os.getcwd()
    regressions_path = os.path.join(base_path, 'regressions')
    regression_tests = get_regression_tests(regressions_path)

    # Check output
    if (verbose):
        for driver in regression_tests:
            print('{}: ['.format(driver))
            for path in regression_tests[driver]:
                print("    '{}',".format(path))
            print(']')

    n_tests = sum(len(t) for t in regression_tests.values())
    print('Number of tests: {}'.format(n_tests))

    # Temporarily dump output to /dev/null
    f_null = open(os.devnull, 'w')

    for reg_test in regression_tests:
        for test_path, _, _ in regression_tests[driver]:
            layout_path = os.path.join(test_path, DOC_LAYOUT)
            params = parse_mom6_param(layout_path)

            ni = int(params['NIPROC'])
            nj = int(params['NJPROC'])
            nprocs = ni * nj

            # Just testing... trying 32 jobs
            # And don't run concurrently
            # And don't bother iterating over compilers
            for compiler in compilers:
                # TODO: repro, [no]symmetric, etc
                exe_path = os.path.join(base_path, 'build', compiler, driver,
                                        'repro', 'MOM6')
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

                    #print('Running {}...'.format(os.path.basename(test_path)))
                    proc = subprocess.Popen(
                        shlex.split(cmd),
                        stdout=f_null,
                        stderr=f_null,
                    )
                    print(proc.pid)

    f_null.close()


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
