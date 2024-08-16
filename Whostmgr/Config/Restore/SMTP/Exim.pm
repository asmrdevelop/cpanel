package Whostmgr::Config::Restore::SMTP::Exim;

# cpanel - Whostmgr/Config/Restore/SMTP/Exim.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Restore::Base);

use Cpanel::LoadFile               ();
use Cpanel::Dir::Loader            ();
use Cpanel::Exim::Config::Install  ();
use Cpanel::Exim::Config::Template ();
use Cpanel::SafeRun::Errors        ();

use Whostmgr::Config::Exim ();

sub _restore {
    my $self   = shift;
    my $parent = shift;

    my $backup_path = $parent->{'backup_path'};
    return ( 0, "Backup Path must be an absolute path" ) if ( $backup_path !~ /^\// );

    return ( 0, "version file missing from backup" ) if !-e "$backup_path/cpanel/smtp/exim/version";

    foreach my $file ( keys %Whostmgr::Config::Exim::exim_files ) {
        my @fullpath = split( /\//, $file );
        my $basefile = $fullpath[-1];
        pop @fullpath;
        my $dir = join( '/', @fullpath );

        if ( $Whostmgr::Config::Exim::exim_files{$file}->{'special'} eq "dry_run" ) {
            $parent->{'files_to_copy'}->{"$backup_path/cpanel/smtp/exim/config/$basefile"} = { 'dir' => $dir, "file" => "$basefile.dry_run" };
        }
        elsif ( $Whostmgr::Config::Exim::exim_files{$file}->{'special'} eq "present" ) {
            $parent->{'files_to_copy'}->{"$backup_path/cpanel/smtp/exim/config/$basefile"} = { 'dir' => $dir, "file" => "$basefile" };

            if ( !-e "$backup_path/cpanel/smtp/exim/config/$basefile" ) {
                $parent->{'files_to_copy'}->{"$backup_path/cpanel/smtp/exim/config/$basefile"}->{'delete'} = 1;
            }
        }
        elsif ( $Whostmgr::Config::Exim::exim_files{$file}->{'special'} eq "dir" ) {
            my $archive_dir = $Whostmgr::Config::Exim::exim_files{$file}{'archive_dir'};
            $parent->{'dirs_to_copy'}->{$file} = { 'archive_dir' => $archive_dir };
        }
    }

    my %ACLBLOCKS   = Cpanel::Dir::Loader::load_multi_level_dir( $backup_path . "/cpanel/smtp/exim/acls" );
    my %DISTED_ACLS = map { $_ => undef } split( /\n/, Cpanel::LoadFile::loadfile('/usr/local/cpanel/etc/exim/acls.dist') );
    delete @DISTED_ACLS{ grep ( /^(?:custom|#)/, keys %DISTED_ACLS ) };

    foreach my $aclblock ( sort keys %ACLBLOCKS ) {
        foreach my $file ( grep { $_ !~ /\.dry_run$/ && !exists $DISTED_ACLS{$_} } @{ $ACLBLOCKS{$aclblock} } ) {
            $parent->{'files_to_copy'}->{"$backup_path/cpanel/smtp/exim/acls/$aclblock/$file"} = { 'dir' => "/usr/local/cpanel/etc/exim/acls/$aclblock", 'file' => "$file.dry_run" };
        }
    }
    my %INFO;
    if ( open( my $version_fh, '<', "$backup_path/cpanel/smtp/exim/version" ) ) {
        %INFO = map { ( split( /=/, $_, 2 ) )[ 0, 1 ] } split( /\n/, readline($version_fh) );
        close($version_fh);
    }
    my $restore_version = Cpanel::Exim::Config::Template::getacltemplateversion("$backup_path/cpanel/smtp/exim/config/exim.conf.local") || $INFO{'version'} || 'unknown';

    return ( 1, __PACKAGE__ . ": ok", { 'version' => $restore_version } );
}

sub post_restore {

    # returns STATUS, MESSAGE, HTML
    my ( $success, $msg, $html ) = Cpanel::Exim::Config::Install::install_exim_configuration_from_dry_run();

    if ($success) {
        Cpanel::SafeRun::Errors::saferunnoerror("/usr/local/cpanel/scripts/restartsrv_exim");
        my @localopts = glob("/var/cpanel/configs.cache/_etc_exim.conf.localopts*");
        foreach my $file (@localopts) {
            unlink $file;
        }
    }

    return;
}

1;
