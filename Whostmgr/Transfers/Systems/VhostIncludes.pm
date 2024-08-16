package Whostmgr::Transfers::Systems::VhostIncludes;

# cpanel - Whostmgr/Transfers/Systems/VhostIncludes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::Config::userdata::Load ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Locale      ();
use Cpanel::SafeDir::MK ();
use Cpanel::SimpleSync  ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub APACHE_USERDATA_DIR {
    return apache_paths_facade->dir_conf_userdata();
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores custom virtual host includes.') ];
}

sub get_restricted_available {
    return 0;
}

sub restricted_restore {
    my ($self) = @_;

    my $include_files_ref = $self->_get_custom_vhost_templates_to_copy();

    if ( @{$include_files_ref} ) {
        return ( $Whostmgr::Transfers::Systems::UNSUPPORTED_ACTION, $self->_locale()->maketext( 'Restricted restorations do not allow running the “[_1]” module.', 'VhostIncludes' ) );    # PPI NO PARSE: use base
    }

    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $include_files_ref = $self->_get_custom_vhost_templates_to_copy();

    foreach my $include_ref (@$include_files_ref) {
        my ( $source, $dest )    = @{$include_ref};
        my ( $status, $message ) = Cpanel::SimpleSync::syncfile( $source, $dest );
        if ( !$status ) {
            $self->warn( $self->_locale()->maketext( 'The system failed to copy the file “[_1]” to “[_2]” because of an error: [_3]', $source, $dest, $message ) );
        }
    }

    return 1;
}

sub _get_custom_vhost_templates_to_copy {
    my ($self) = @_;

    my @include_files;
    my $newuser      = $self->newuser();
    my $extractdir   = $self->extractdir();
    my $user_homedir = $self->homedir();

    $self->start_action("Restoring custom virtualhost templates…\n");
    my $from_base = "$extractdir/httpfiles";

    # No need to lock, because we are not going to save.
    my $main_userdata = Cpanel::Config::userdata::Load::load_userdata_main($newuser);

    my @user_vhosts;
    if ( $main_userdata->{'main_domain'} )                                            { push @user_vhosts, $main_userdata->{'main_domain'}; }
    if ( $main_userdata->{'sub_domains'} && ref $main_userdata->{'sub_domains'} )     { push @user_vhosts, @{ $main_userdata->{'sub_domains'} }; }
    if ( $main_userdata->{'addon_domains'} && ref $main_userdata->{'addon_domains'} ) { push @user_vhosts, keys %{ $main_userdata->{'addon_domains'} }; }

  VHOST:
    for my $vhost (@user_vhosts) {

      PROTOCOL:
        for my $proto (qw( std ssl )) {

          VERSION:
            for my $ver ( 1, 2 ) {

                my $from_path = "$from_base/$proto/$ver/$vhost";

                next VERSION if !-e $from_path;

                my $dest_dir = APACHE_USERDATA_DIR() . "/$proto/$ver/$newuser/$vhost";

                Cpanel::SafeDir::MK::safemkdir( $dest_dir, 0700 ) or do {
                    $self->warn( $self->_locale()->maketext( 'The system failed to create the directory “[_1]” because of an error: [_2]', $dest_dir, $! ) );
                    next VERSION;
                };

                opendir( my $dir_h, $from_path ) or do {
                    $self->warn( $self->_locale()->maketext( 'The system failed to open the directory “[_1]” because of an error: [_2]', $from_path, $! ) );
                    next VERSION;
                };

                local $!;
                my @templates = grep { !/^\./ } readdir($dir_h);
                if ($!) {
                    $self->warn( $self->_locale()->maketext( 'The system failed to read the directory “[_1]” because of an error: [_2]', $from_path, $! ) );
                    next VERSION;
                }

                closedir $dir_h or do {
                    $self->warn( $self->_locale()->maketext( 'The system failed to close the directory “[_1]” because of an error: [_2]', $from_path, $! ) );
                    next VERSION;
                };

                foreach my $file (@templates) {
                    push @include_files, [ "$from_path/$file", $dest_dir ];
                }
            }
        }
    }

    return \@include_files;
}

1;
