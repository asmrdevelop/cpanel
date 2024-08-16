package Whostmgr::Exim::Config;

# cpanel - Whostmgr/Exim/Config.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Rand             ();
use Cpanel::StringFunc::Trim ();
use Cpanel::SafeRun::Errors  ();
use Cpanel::SafeRun::Simple  ();
use Cpanel::Dir::Loader      ();

our @CFG_FILES = ( 'local', 'localopts', 'localopts.shadow' );

sub validate_current_installed_exim_config {
    require File::Copy;

    my %files;
    foreach my $file (@CFG_FILES) {
        my ( $tmpfile, $fh ) = Cpanel::Rand::get_tmp_file_by_name( '/etc/exim.conf.' . $file . '.validate' );

        # If this file exists, then it will be copied into the temporary
        # /etc/exim.conf.$file.validate file and saved in the %files hash.
        # Otherwise, nothing should happen.
        if ( $tmpfile && File::Copy::copy( "/etc/exim.conf.$file", $fh ) ) {
            $files{$file} = $tmpfile;
        }
    }
    my @ret = attempt_exim_config_update( 'dry_run_only' => 1, 'files' => \%files );
    unlink( values %files );
    return @ret;
}

sub attempt_exim_config_update {
    my %OPTS = @_;
    my @args;
    my @files;
    if ( ref $OPTS{'files'} eq 'ARRAY' ) {
        foreach my $file ( @{ $OPTS{'files'} } ) {
            if    ( $file eq 'local' )            { push @args, '--local=/etc/exim.conf.local.dry_run'; }
            elsif ( $file eq 'localopts' )        { push @args, '--localopts=/etc/exim.conf.localopts.dry_run'; }
            elsif ( $file eq 'localopts.shadow' ) { push @args, '--localopts.shadow=/etc/exim.conf.localopts.shadow.dry_run'; }
        }
        @files = @{ $OPTS{'files'} };
    }
    elsif ( ref $OPTS{'files'} eq 'HASH' ) {
        foreach my $file ( keys %{ $OPTS{'files'} } ) {
            push @args, "--" . $file . "=" . $OPTS{'files'}->{$file};
        }
        @files = keys %{ $OPTS{'files'} };
    }
    push @args, '--acl_dry_run' if $OPTS{'acl_dry_run'};

    ### Rebuild/test/restore
    my $html = "<pre>";
    {
        local $SIG{'CHLD'} = 'DEFAULT';
        $html .= "Doing Dry Run\n";
        $html .= Cpanel::SafeRun::Errors::saferunallerrors( "/usr/local/cpanel/scripts/buildeximconf", @args );
    }
    $html .= '</pre>';
    my $conf_exit = $? >> 8;

    if ( $conf_exit == 0 ) {
        return ( 1, "Your configuration is currently valid.", $html ) if $OPTS{'dry_run_only'};

        # Write out all settings
        $html .= "<pre>";
        {
            local $SIG{'CHLD'} = 'DEFAULT';
            foreach my $file (@files) {
                $html .= Cpanel::SafeRun::Errors::saferunallerrors( 'mv', '-fv', "/etc/exim.conf.$file.dry_run", "/etc/exim.conf.$file" );
            }
            if ( ref $OPTS{'acls_to_install'} ) {
                foreach my $acl ( @{ $OPTS{'acls_to_install'} } ) {
                    $html .= Cpanel::SafeRun::Errors::saferunallerrors( 'mv', '-fv', "/usr/local/cpanel/etc/exim/acls/$acl.dry_run", "/usr/local/cpanel/etc/exim/acls/$acl" );
                }
            }

            $html .= Cpanel::SafeRun::Errors::saferunallerrors("/usr/local/cpanel/scripts/buildeximconf");
        }
        $html .= '</pre>';
        return ( 1, "Your configuration changes have been saved!", $html );
    }
    else {
        return ( 0, "Your configuration is currently invalid.", $html ) if $OPTS{'dry_run_only'};
        return ( 0, "Your configuration could not be updated.", $html );
    }
}

sub configuration_check {
    my $config_check = Cpanel::StringFunc::Trim::ws_trim( Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/check_exim_config', '--checkonly', '--quiet' ) );

    if ($config_check) {
        return ( 0, 'Configuration Update Failed', $config_check );
    }
    return ( 1, 'Configuration OK' );
}

sub remove_in_progress_exim_config_edit {
    foreach my $file (@CFG_FILES) {
        unlink '/etc/exim.conf.' . $file . '.dry_run';
    }
    my %ACLBLOCKS = Cpanel::Dir::Loader::load_multi_level_dir('/usr/local/cpanel/etc/exim/acls');
    foreach my $aclblock ( sort keys %ACLBLOCKS ) {
        foreach my $file ( grep( /\.dry_run$/, @{ $ACLBLOCKS{$aclblock} } ) ) {
            unlink("/usr/local/cpanel/etc/exim/acls/$aclblock/$file");
        }
    }
    return ( 1, "Removed OK" );
}

1;
