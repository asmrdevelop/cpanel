package Whostmgr::API::1::PackageManager;

# cpanel - Whostmgr/API/1/PackageManager.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Form::Param     ();
use Cpanel::Rlimit          ();
use Cpanel::ArrayFunc::Uniq ();

use constant NEEDS_ROLE => {
    package_manager_fixcache              => undef,
    package_manager_get_build_log         => undef,
    package_manager_get_package_info      => undef,
    package_manager_is_performing_actions => undef,
    package_manager_list_packages         => undef,
    package_manager_resolve_actions       => undef,
    package_manager_submit_actions        => undef,
    package_manager_upgrade               => undef,
};

sub package_manager_fixcache {
    my ( $args, $metadata ) = @_;

    # try to fix it
    my $original_rlimits = Cpanel::Rlimit::get_current_rlimits();
    Cpanel::Rlimit::set_rlimit_to_infinity();    # otherwise python barfs: thread.error: can't start new thread
    require Cpanel::PackMan;
    eval { Cpanel::PackMan->instance->sys->cache(); };
    Cpanel::Rlimit::restore_rlimits($original_rlimits);
    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = "OK";

    return { cache_seems_ok_now => 1 };
}

sub package_manager_list_packages {
    my ( $args, $metadata ) = @_;

    my @packages;

    require Cpanel::PackMan;
    eval {
        my $pkm = Cpanel::PackMan->instance;

        # We may pass query params
        # but, we'll need to coordinate with API filtering mechanism
        @packages = exists $args->{state} ? $pkm->list( state => $args->{state} ) : $pkm->list();
        @packages = map { { 'package' => $_ } } @packages;
    };
    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'packages' => \@packages };
}

sub package_manager_get_package_info {
    my ( $args, $metadata ) = @_;

    my $params           = Cpanel::Form::Param->new( { parseform_hr => $args } );
    my @packages         = $params->param('package');
    my @prefixes         = map { "$_-" } $params->param('ns');
    my $disable_excludes = $params->param('disable-excludes');

    if ( !@packages && !@prefixes ) {
        die "package_manager_get_package_info requires at least one “package” or “ns” argument.";
    }

    require Cpanel::PackMan;
    my $pkm     = Cpanel::PackMan->instance;
    my $results = $pkm->multi_pkg_info( 'prefixes' => \@prefixes, 'packages' => \@packages, 'disable-excludes' => $disable_excludes );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'packages' => $results };
}

sub package_manager_submit_actions {
    my ( $args, $metadata ) = @_;

    my $pid;

    require Cpanel::PackMan;
    eval {
        my $req = Cpanel::Form::Param->new( { parseform_hr => $args } );

        my $pkm = Cpanel::PackMan->instance;

        $pid = $pkm->build->start(
            sub {
                $pkm->multi_op(
                    {
                        install   => [ $req->param('install') ],
                        upgrade   => [ $req->param('upgrade') ],
                        uninstall => [ $req->param('uninstall') ],
                    }
                );
            },
        );
    };
    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
        return;
    }

    if ( !defined $pid ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Package actions are already running';
        return;
    }

    if ( $pid == 0 ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Failed to start package actions';
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { build => $pid };
}

sub package_manager_upgrade {
    my ( $args, $metadata ) = @_;

    my $params = Cpanel::Form::Param->new( { parseform_hr => $args } );

    my $pid;

    require Cpanel::PackMan;
    eval {
        my $pkm    = Cpanel::PackMan->instance;
        my $kernel = $params->param('kernel');
        if ( !defined $kernel || $kernel =~ m/false/ ) {
            $pid = $pkm->build->start( sub { $pkm->sys->upgrade('--exclude=kernel-*') } );
        }
        else {
            $pid = $pkm->build->start( sub { $pkm->sys->upgrade() } );
        }
    };
    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
        return;
    }

    if ( !defined $pid ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Package actions are already running';
        return;
    }

    if ( $pid == 0 ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Failed to start package actions';
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { build => $pid };
}

sub package_manager_is_performing_actions {
    my ( $args, $metadata ) = @_;

    require Cpanel::PackMan;
    my $result;
    eval { $result = Cpanel::PackMan->instance->build->is_running() ? 1 : 0; };
    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'active' => $result };
}

our $_get_build_log_max_lines = 50;

sub package_manager_get_build_log {
    my ( $args, $metadata ) = @_;

    my $output_ref = {};

    require Cpanel::PackMan;
    eval {
        my $req = Cpanel::Form::Param->new( { parseform_hr => $args } );
        my $pkm = Cpanel::PackMan->instance;

        my $build  = $req->param('build');
        my $offset = $req->param('offset');

        die "Invalid Build Parameter\n" if !defined $build || !length($build) || $build =~ m/[^0-9]/ || abs( int($build) ) != $build;

        $offset = 0 if !defined $offset;

        die "Invalid Offset\n" if !length($offset) || $offset =~ m/[^0-9]/ || abs( int($offset) ) != $offset;

        # This tail file discovery could be removed if $pkm->build->start created
        # a $pkm->build->log_dir/pids/$build symlink pointing to the the target file
        # and we just open it below
        my $tailfile;

        for my $pidfile ( glob( $pkm->build->log_dir . "/*/.*.pid" ) ) {
            open my $fh, "<", $pidfile or die "Cannot open packman pid file";
            my $pid = readline $fh;
            chomp($pid);
            close $fh;

            if ( $pid == $build ) {
                $tailfile = substr( $pidfile, 0, -4 );
                last;
            }
        }

        die "Build ID does not exist\n" if !defined $tailfile;

        open my $FH, "<", $tailfile or die "Cannot open log file ($tailfile)\n$!";
        seek $FH, $offset, 0;
        my $line_count = 0;
        $output_ref->{'content'} = [];

        while (<$FH>) {
            chomp;

            push( @{ $output_ref->{'content'} }, $_ );
            $line_count++;

            # prevent a runaway log tailer if the source process never pauses
            last if $line_count >= $_get_build_log_max_lines;
        }

        $offset = tell $FH;
        close $FH;

        $output_ref->{'offset'}        = $offset;
        $output_ref->{'still_running'} = $output_ref->{'content'}->[-1] eq "-- /$build --" ? 0 : 1;
    };

    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;    # above die messages must end in newlines

        return;
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }

    return $output_ref;
}

sub package_manager_resolve_actions {
    my ( $args, $metadata ) = @_;

    my $req      = Cpanel::Form::Param->new( { parseform_hr => $args } );
    my @packages = $req->param('package');
    die "One or more 'package' parameters is required.\n" if !@packages;    # would be nice if we could throw a 400 like real APIs …
    my @nss = $req->param('ns');
    if ( !@nss ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Namespace is required.';
        return;
    }

    require Cpanel::PackMan;
    my $pkm = Cpanel::PackMan->instance;

    my $multi_op;
    for my $ns (@nss) {
        my $ns_multi_op = eval { $pkm->resolve_multi_op_ns( \@packages, $ns, 1 ) };
        if ($@) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $@;
            return;
        }

        for my $field (qw(uninstall unaffected upgrade install)) {
            $ns_multi_op->{$field} //= [];
            push @{ $multi_op->{$field} }, @{ $ns_multi_op->{$field} };
        }
    }

    # remove possible duplicates
    for my $field (qw(uninstall unaffected upgrade install)) {
        my @array = Cpanel::ArrayFunc::Uniq::uniq( @{ $multi_op->{$field} } );
        $multi_op->{$field} = \@array;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return $multi_op;
}

1;
