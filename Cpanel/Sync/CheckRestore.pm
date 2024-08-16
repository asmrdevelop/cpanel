package Cpanel::Sync::CheckRestore;

# cpanel - Cpanel/Sync/CheckRestore.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Config::Sources ();
use Cpanel::MD5             ();
use Cpanel::Sync::v2        ();
use Cpanel::Sys::Hostname   ();
use Cpanel::Update::Config  ();
use Cpanel::Update::Logger  ();
use Cpanel::Version::Full   ();

=head1 NAME

Cpanel::Sync::CheckRestore - restores a cPanel file to its original state.

=head1 NOTE

NOTE: cPanel Sync CheckRestore is subject to change or removal at any time without notice so proceed with caution!

=head1 SYNOPSIS

If, after cPanel installation or update, a file under /usr/local/cpanel is either:
    - deleted
    - modified
    - changed to a symlink to another file

The check_and_restore function will try to download the original file and restore it.

=cut

sub check_and_restore {
    my ($source_file) = @_;

    $source_file = $source_file =~ m/^\/cpanel\// ? $source_file : '/cpanel/' . $source_file;

    my $cp_sources = Cpanel::Config::Sources::loadcpsources();
    my $cp_version = Cpanel::Version::Full::getversion();

    # We're doing this to suppress a small amount of output we don't want emitted.
    my $logger = Cpanel::Update::Logger->new( { 'stdout' => 0, 'log_level' => 'error' } ) or return;

    my $staging_dir = _determine_staging_dir();
    my $ulc         = _determine_ulc();
    my $target_file = $source_file;
    $target_file =~ s{^/cpanel/}{};
    $target_file = $ulc . '/' . $target_file;

    my %basic_options = (
        'syncto'      => $staging_dir,
        'url'         => 'http://' . $cp_sources->{'HTTPUPDATE'} . '/cpanelsync/' . $cp_version,
        'source'      => ['cpanel'],
        'logger'      => $logger,
        'staging_dir' => $staging_dir,
        'ulc'         => $ulc
    );

    my $v2;
    eval { $v2 = Cpanel::Sync::v2->new( {%basic_options} ); 1 } or return;
    eval { $v2->stage_cpanelsync_files();                   1 } or return;
    eval { $v2->parse_new_cpanelsync_files();               1 } or return;

    my $file_info = $v2->{'source_data'}->{'sync_file_data'}->{'cpanel'}->{$target_file};

    return unless defined $file_info->{'perm'};

    my $staged_to;
    eval { $staged_to = $v2->stage_file( $source_file, $target_file, $file_info ) };

    return if !-e $staged_to || !defined( $v2->{'staged_files'}->{$target_file} ) || !$v2->{'staged_files'}->{$target_file}->[$Cpanel::Sync::v2::STATE_KEY_POSITION];

    if ( !-e $target_file || Cpanel::MD5::getmd5sum($staged_to) ne Cpanel::MD5::getmd5sum($target_file) ) {
        eval { $v2->commit_files() };
    }

    return;
}

sub _determine_staging_dir {
    my $upconf      = Cpanel::Update::Config::load();
    my $staging_dir = $upconf->{'STAGING_DIR'};

    if ( $staging_dir !~ m{^/usr/local/cpanel/?$} ) {
        my $hostname = Cpanel::Sys::Hostname::gethostname();
        $hostname =~ s/\./_/g;
        $staging_dir .= ( substr( $staging_dir, -1 ) eq '/' ? ".cpanel__${hostname}__upcp_staging" : "/.cpanel__${hostname}__upcp_staging" );
    }

    return $staging_dir;
}

sub _determine_ulc {
    return '/usr/local/cpanel';
}

1;
