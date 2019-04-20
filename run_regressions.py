#!/usr/bin/env python
import collections
import errno
import filecmp
import os
import shlex
import shutil
import subprocess


DOC_LAYOUT = 'MOM_parameter_doc.layout'
verbose = True


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

    n_tests = sum(len(t) for t in regression_tests['gnu'].values())
    print('Number of tests: {}'.format(n_tests))

    for compiler in regression_tests:
        # TODO: static, [no]symmetric, etc
        for build in ('repro',):
            running_tests = []
            for config in regression_tests[compiler]:
                for reg_path, test_path in regression_tests[compiler][config]:
                    # Only do circle_obcs for symmetric domains
                    # TODO: Check for symmetric in MOM_parameters_doc.* ?
                    if (os.path.basename(test_path) == 'circle_obcs' and
                            build != 'symmetric'):
                        continue

                    test = RegressionTest()
                    test.refpath = reg_path
                    test.runpath = test_path

                    prefix = os.path.join(base_path, 'regressions', config)
                    test.name = reg_path[len(prefix + os.sep):]

                    layout_path = os.path.join(test.runpath, DOC_LAYOUT)
                    params = parse_mom6_param(layout_path)

                    ni = int(params['NIPROC'])
                    nj = int(params['NJPROC'])
                    nprocs = ni * nj

                    exe_path = os.path.join(
                        base_path, 'build', compiler, config, build, 'MOM6'
                    )

                    # For now just test 1-node jobs
                    if nprocs <= 16:
                        # Set up output directories
                        # TODO: Ditch logpath, keep paths to stats file
                        test.logpath = os.path.join(base_path, 'output', config, test.name)
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
                            '--exclusive',
                            '-n {}'.format(nprocs),
                        ])

                        cmd = '{launcher} {flags} {exe}'.format(
                            launcher='srun',
                            flags=srun_flags,
                            exe=exe_path
                        )

                        if (verbose):
                            print('Running {}...'.format(test.name))

                        proc = subprocess.Popen(
                            shlex.split(cmd),
                            stdout=test.stdout,
                            stderr=test.stderr,
                        )
                        test.process = proc

                        running_tests.append(test)

            # Wait for processes to complete
            # TODO: Cycle through and check them all, not just the first slow one
            for test in running_tests:
                test.process.wait()

            # Check if any runs exited with an error
            if all(test.process.returncode == 0 for test in running_tests):
                print('All tested completed!')
            else:
                for test in running_tests:
                    if test.process.returncode != 0:
                        print('Test {} failed with code {}'.format(
                            test.name, test.process.returncode
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

            # Compare output
            for test in running_tests:
                print('{} Match?: {}'.format(test.name, test.check_stats()))


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
                for ref in ref_stats
                for stat in self.stats
            )
        else:
            match = False

        return match


if __name__ == '__main__':
    regressions()
