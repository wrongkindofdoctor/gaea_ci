#!/usr/bin/env python
import collections
import errno
import filecmp
import os
import shlex
import shutil
import subprocess

import f90nml

NPROCS_MAX = 480
#NPROCS_MAX = 32
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
                print('    {}:'.format(config))
                for reg, test in regression_tests[compiler][config]:
                    print('        {}'.format(reg))
                    print('        {}'.format(test))
            print(']')

    n_tests = sum(len(t) for t in regression_tests['pgi'].values())
    print('Number of tests: {}'.format(n_tests))

    for compiler in regression_tests:
        for mode in ('repro',):
            running_tests = []
            for config in regression_tests[compiler]:
                for reg_path, test_path in regression_tests[compiler][config]:
                    test = RegressionTest()
                    test.refpath = reg_path
                    test.runpath = test_path

                    prefix = os.path.join(base_path, 'regressions', config)
                    test.name = reg_path[len(prefix + os.sep):]

                    mom_layout_path = os.path.join(test.runpath, 'MOM_layout')
                    if os.path.isfile(mom_layout_path):
                        layout_params = parse_mom6_param(mom_layout_path)
                        layout = layout_params['LAYOUT']
                        ocean_ni, ocean_nj = (int(n) for n in layout.split(','))

                        masktable = layout_params.get('MASKTABLE')
                        if masktable:
                            n_mask = int(masktable.split('.')[1])
                        else:
                            n_mask = 0
                    else:
                        layout_path = os.path.join(test.runpath, DOC_LAYOUT)
                        params = parse_mom6_param(layout_path)

                        # If a run crashes, its proc count may be incorrect
                        # TODO: Re-checkout the files?
                        if not any(p in params for p in ('NIPROC', 'NJPROC')):
                            print('ERROR: {} missing CPU layout'.format(test.name))
                            continue

                        ocean_ni = int(params['NIPROC'])
                        ocean_nj = int(params['NJPROC'])

                        n_mask = 0

                    input_nml_path = os.path.join(test.runpath, 'input.nml')
                    input_nml = f90nml.read(input_nml_path)
                    coupler_nml = input_nml.get('coupler_nml', {})
                    atmos_npes = coupler_nml.get('atmos_npes', 0)
                    ocean_npes = coupler_nml.get('ocean_npes')

                    if ocean_npes:
                        assert(ocean_npes == ocean_ni * ocean_nj)
                    else:
                        ocean_npes = ocean_ni * ocean_nj

                    nprocs = (ocean_npes - n_mask) + atmos_npes

                    # XXX: I am running both in the same directory!!
                    #for grid in ('dynamic', 'dynamic_symmetric'):
                    for grid in ('dynamic_symmetric', ):
                        # OBC tests require symmetric grids
                        if (os.path.basename(test_path) == 'circle_obcs' and
                                grid != 'dynamic_symmetric'):
                            continue

                        exe_path = os.path.join(
                            base_path, 'MOM6-examples', 'build', compiler,
                            mode, grid, config, 'MOM6'
                        )

                        if nprocs > NPROCS_MAX:
                            print('{}: skipping {} ({} ranks)'.format(
                                compiler, test.name, nprocs
                            ))
                            continue

                        # Set up output directories
                        # TODO: Ditch logpath, keep paths to stats file
                        test.logpath = os.path.join(
                            base_path, 'output', config, grid, test.name
                        )
                        mkdir_p(test.logpath)

                        stdout_path = os.path.join(test.logpath, compiler + '.out')
                        stderr_path = os.path.join(test.logpath, compiler + '.err')

                        test.stdout = open(stdout_path, 'w')
                        test.stderr = open(stderr_path, 'w')

                        # FMS requires an existing RESTART directory
                        os.chdir(test_path)
                        mkdir_p('RESTART')

                        # Stage the Slurm command
                        srun_flags = ' '.join([
                            '-mblock',
                            '--exclusive',
                            '-n {}'.format(nprocs),
                        ])

                        cmd = '{launcher} {flags} {exe}'.format(
                            launcher='srun',
                            flags=srun_flags,
                            exe=exe_path
                        )

                        if (verbose):
                            print('    Starting {}...'.format(test.name))

                        proc = subprocess.Popen(
                            shlex.split(cmd),
                            stdout=test.stdout,
                            stderr=test.stderr,
                        )
                        test.process = proc

                        running_tests.append(test)

            print('{}: Running {} tests.'.format(compiler, len(running_tests)))

            # Wait for processes to complete
            # TODO: Cycle through and check them all, not just the first slow one
            for test in running_tests:
                test.process.wait()

            # Check if any runs exited with an error
            if all(test.process.returncode == 0 for test in running_tests):
                print('{}: Tests finished, no errors!'.format(compiler))
            else:
                for test in running_tests:
                    if test.process.returncode != 0:
                        print('{}: Test {} failed with code {}'.format(
                            compiler, test.name, test.process.returncode
                        ))

            # Process cleanup
            # TODO: Make a class method
            for test in running_tests:
                # Store the stats files
                stat_files = [
                   f for f in os.listdir(test.runpath)
                   if f.endswith('.stats')
                ]
                for fname in stat_files:
                    src = os.path.join(test.runpath, fname)
                    dst = os.path.join(test.logpath, fname) + '.' + compiler
                    shutil.copy(src, dst)

                    # Add to logs
                    test.stats.append(dst)

                test.stdout.close()
                test.stderr.close()

            # Compare stats to reference
            test_results = {}
            for test in running_tests:
                test_results[test.name] = test.check_stats()

            if any(result == False for result in test_results.values()):
                for test in test_results:
                    if test_results[test] == False:
                        print('FAIL: {}'.format(test))
            else:
                print('{}: No regressions, test passed!'.format(compiler))


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


class RegressionTest(object):
    def __init__(self):
        self.runpath = None
        self.logpath = None
        self.refpath = None

        self.stats = []

        self.process = None

        self.stdout = None
        self.stderr = None

    def check_stats(self):
        """Compare test stat results with regressions."""

        ref_stats = [
            os.path.join(self.refpath, os.path.basename(stat))
            for stat in self.stats
        ]

        if self.stats:
            match = all(
                filecmp.cmp(ref, stat)
                for ref, stat in zip(ref_stats, self.stats)
            )
        else:
            match = False

        return match


if __name__ == '__main__':
    regressions()
