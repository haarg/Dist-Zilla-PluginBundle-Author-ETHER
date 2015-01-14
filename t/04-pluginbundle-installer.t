use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::Deep;
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Module::Runtime 'require_module';
use List::Util 1.33 'none';

use Test::Requires qw(
    Dist::Zilla::Plugin::ModuleBuildTiny
);

use Test::File::ShareDir -share => { -dist => { 'Dist-Zilla-PluginBundle-Author-ETHER' => 'share' } };

use lib 't/lib';
use Helper;
use NoNetworkHits;
use NoPrereqChecks;

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does_not_exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    'GatherDir',
                    # our files are copied into source, so Git::GatherDir doesn't see them
                    # and besides, we would like to run these tests at install time too!
                    [ '@Author::ETHER' => {
                        '-remove' => [ 'Git::GatherDir', 'Git::NextVersion', 'Git::Describe',
                            'Git::Contributors', 'Git::Check', 'Git::Commit', 'Git::Tag', 'Git::Push',
                            'Git::CheckFor::MergeConflicts', 'Git::CheckFor::CorrectBranch',
                            'Git::Remote::Check', 'PromptIfStale', 'EnsurePrereqsInstalled' ],
                        server => 'none',
                        installer => 'MakeMaker',
                        'RewriteVersion::Transitional.skip_version_provider' => 1,
                      },
                    ],
                ),
                path(qw(source lib MyDist.pm)) => "package MyDist;\n\n1",
            },
        },
    );

    my @git_plugins = grep { $_->meta->name =~ /Git(?!(?:hubMeta|Hub::Update))/ } @{$tzil->plugins};
    cmp_deeply(\@git_plugins, [], 'no git-based plugins are running here');

    $tzil->chrome->logger->set_debug(1);
    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    # check that everything we loaded is properly declared as prereqs
    all_plugins_in_prereqs($tzil,
        exempt => [ 'Dist::Zilla::Plugin::GatherDir' ],     # used by us here
        additional => [ 'Dist::Zilla::Plugin::MakeMaker' ], # via installer option
    );

    cmp_deeply(
        [ $tzil->plugin_named('@Author::ETHER/MakeMaker') ],
        [ methods(default_jobs => 9) ],
        'installer configuration settings are properly added to the payload',
    );

    my $build_dir = path($tzil->tempdir)->child('build');
    my @found_files;
    my $iter = $build_dir->iterator({ recurse => 1 });
    while (my $path = $iter->())
    {
        push @found_files, $path->relative($build_dir)->stringify if -f $path;
    }

    cmp_deeply(
        \@found_files,
        all(
            superbagof('Makefile.PL'),
            code(sub { none { $_ eq 'Build.PL' } @{$_[0]} }),
        ),
        'Makefile.PL (and no other build file) was generated by the pluginbundle',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}

SKIP: {
    # MBT is already a prereq of things in our runtime recommends list
    skip('[ModuleBuildTiny] not installed', 1)
        if not eval { require_module 'Dist::Zilla::Plugin::ModuleBuildTiny'; 1 };

    my $tzil = Builder->from_config(
        { dist_root => 't/does_not_exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    'GatherDir',
                    # our files are copied into source, so Git::GatherDir doesn't see them
                    # and besides, we would like to run these tests at install time too!
                    [ '@Author::ETHER' => {
                        '-remove' => [ 'Git::GatherDir', 'Git::NextVersion', 'Git::Describe',
                            'Git::Contributors', 'Git::Check', 'Git::Commit', 'Git::Tag', 'Git::Push',
                            'Git::CheckFor::MergeConflicts', 'Git::CheckFor::CorrectBranch',
                            'Git::Remote::Check', 'PromptIfStale', 'EnsurePrereqsInstalled' ],
                        server => 'none',
                        installer => [ qw(MakeMaker ModuleBuildTiny) ],
                        'RewriteVersion::Transitional.skip_version_provider' => 1,
                      },
                    ],
                ),
                path(qw(source lib MyModule.pm)) => "package MyModule;\n\n1",
            },
        },
    );

    my @git_plugins = grep { $_->meta->name =~ /Git(?!(?:hubMeta|Hub::Update))/ } @{$tzil->plugins};
    cmp_deeply(\@git_plugins, [], 'no git-based plugins are running here');

    $tzil->chrome->logger->set_debug(1);
    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    # check that everything we loaded is properly declared as prereqs
    all_plugins_in_prereqs($tzil,
        exempt => [ 'Dist::Zilla::Plugin::GatherDir' ],     # used by us here
        additional => [
            'Dist::Zilla::Plugin::MakeMaker',       # via installer option
            'Dist::Zilla::Plugin::ModuleBuildTiny', # ""
        ],
    );

    cmp_deeply(
        $tzil->distmeta->{prereqs}{develop}{requires},
        superhashof({
            'Dist::Zilla::Plugin::ModuleBuildTiny' => '0.004',
        }),
        'installer prereq version is added',
    ) or diag 'got dist metadata: ', explain $tzil->distmeta;

    cmp_deeply(
        [
            $tzil->plugin_named('@Author::ETHER/MakeMaker'),
            $tzil->plugin_named('@Author::ETHER/ModuleBuildTiny'),
        ],
        [
            methods(default_jobs => 9),
            methods(default_jobs => 9),
        ],
        'installer configuration settings are properly added to the payload',
    );

    my $build_dir = path($tzil->tempdir)->child('build');
    my @found_files;
    my $iter = $build_dir->iterator({ recurse => 1 });
    while (my $path = $iter->())
    {
        push @found_files, $path->relative($build_dir)->stringify if -f $path;
    }

    cmp_deeply(
        \@found_files,
        superbagof(qw(
            Makefile.PL
            Build.PL
        )),
        'both Makefile.PL and Build.PL were generated by the pluginbundle',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}

done_testing;
