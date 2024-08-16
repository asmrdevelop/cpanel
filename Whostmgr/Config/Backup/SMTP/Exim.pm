package Whostmgr::Config::Backup::SMTP::Exim;

# cpanel - Whostmgr/Config/Backup/SMTP/Exim.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Backup::Base );

use Cpanel::LoadFile               ();
use Cpanel::Dir::Loader            ();
use Cpanel::Exim::Config::Template ();
use Cpanel::SafeRun::Errors        ();

use Whostmgr::Config::Exim ();

sub _backup {
    my $self   = shift;
    my $parent = shift;

    my $files_to_copy = $parent->{'files_to_copy'}->{'cpanel::smtp::exim'} = {};
    my $dirs_to_copy  = $parent->{'dirs_to_copy'}->{'cpanel::smtp::exim'}  = {};

    foreach my $cfg_file ( keys %Whostmgr::Config::Exim::exim_files ) {
        my $special = $Whostmgr::Config::Exim::exim_files{$cfg_file}{'special'};
        if ( $special eq "dir" ) {
            my $archive_dir = $Whostmgr::Config::Exim::exim_files{$cfg_file}{'archive_dir'};
            $dirs_to_copy->{$cfg_file} = { "archive_dir" => $archive_dir };
        }
        else {
            $files_to_copy->{$cfg_file} = { "dir" => "cpanel/smtp/exim/config" };
        }
    }

    my %ACLBLOCKS   = Cpanel::Dir::Loader::load_multi_level_dir('/usr/local/cpanel/etc/exim/acls');
    my %DISTED_ACLS = map { $_ => undef } split( /\n/, Cpanel::LoadFile::loadfile('/usr/local/cpanel/etc/exim/acls.dist') );
    delete @DISTED_ACLS{ grep ( /^(?:custom|#)/, keys %DISTED_ACLS ) };

    foreach my $aclblock ( sort keys %ACLBLOCKS ) {
        foreach my $file ( grep { $_ !~ /\.dry_run$/ && !exists $DISTED_ACLS{$_} } @{ $ACLBLOCKS{$aclblock} } ) {

            $files_to_copy->{"/usr/local/cpanel/etc/exim/acls/$aclblock/$file"} = { "dir" => "cpanel/smtp/exim/acls/$aclblock" };
        }
    }

    return ( 1, __PACKAGE__ . ": ok" );
}

use constant _TEMPLATE_VERSIONS => (
    '/etc/exim.conf.local',
    '/etc/exim.conf',
    '/usr/local/cpanel/etc/exim/defacls/universal.dist',
);

sub version {
    my $version;

    for my $path ( _TEMPLATE_VERSIONS() ) {
        $version = Cpanel::Exim::Config::Template::getacltemplateversion($path);
        last if $version;
    }

    return $version;
}

sub query_module_info {
    my %info;
    $info{'EXIM'} = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/sbin/exim', '-bV' );
    eval {
        if ( defined( $info{'EXIM'} ) ) {
            if ( $info{'EXIM'} =~ m/([0-9]+\.[0-9_]+ \#[0-9]+)/ ) {
                $info{'EXIM'} = $1;
            }
            else {
                $info{'EXIM'} = 'Unknown';
            }
        }
        $info{'EXIM_CONFIG'} = ( $info{'EXIM_CONFIG'} =~ m{([0-9]+\.[0-9]+)} )[0] if defined $info{'EXIM_CONFIG'};
    };

    if ( open( my $fh, '<', '/etc/exim.conf' ) ) {
        while ( my $line = <$fh> ) {
            if ( $line =~ m/ACL Template Version:\s+(.\d+\.\d+)$/ ) {
                $info{'EXIM_CONFIG'} = $1;
            }
        }
        close($fh);
    }
    else {
        $info{'EXIM_CONFIG'} = 'Unknown';
    }
    return \%info;
}

1;
