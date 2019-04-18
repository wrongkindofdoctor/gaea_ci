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


def regressions():
    base_path = os.getcwd()

    # Generate list of tests based on existence of stat files
    regressions = collections.defaultdict(list)

    regressions_path = os.path.join(base_path, 'regressions')
    for driver in os.listdir(regressions_path):
        driver_regpath = os.path.join(regressions_path, driver)
        for path, dirs, files in os.walk(driver_regpath):
            if any(f.startswith('ocean.stats') for f in os.listdir(path)):
                expt_path = os.path.join(
                    base_path,
                    'MOM6-examples',
                    path[1 + len(regressions_path):],
                )
                regressions[driver].append(expt_path)

    # Check output
    if (verbose):
        for driver in regressions:
            print('{}: ['.format(driver))
            for path in regressions[driver]:
                print("    '{}',".format(path))
            print(']')

    n_tests = sum(len(t) for t in regressions.values())
    print('Number of tests: {}'.format(n_tests))

    sys.exit()

    # Temporarily dump output to /dev/null
    f_null = open(os.devnull, 'w')

    for driver in model_drivers:
        for test_path in regressions[driver]:
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
