package Whostmgr::Transfers::ConvertAddon::MigrateData::Autoresponders;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/Autoresponders.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use File::Spec                           ();
use Cpanel::TempFile                     ();
use Cpanel::PwCache                      ();
use Cpanel::FileUtils::Copy              ();
use Whostmgr::Email::Autoresponders      ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Exception                    ();

sub copy_auto_responders_for_domain {
    my ( $self, $domain ) = @_;

    if ( !$domain ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a domain name' );    ## no extract maketext (developer error message. no need to translate)
    }

    $self->ensure_users_exist();

    my $old_auto_respond_dir = Whostmgr::Email::Autoresponders::get_auto_responder_dir( $self->{'from_username'} );
    return 1 if !-d $old_auto_respond_dir;

    my ( $from_user_uid, $from_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'from_username'} ) )[ 2, 3 ];
    my $responders = Whostmgr::Email::Autoresponders::list_auto_responders_for_domain( { 'user' => $self->{'from_username'}, 'domain' => $domain } );

    my $temp_dir;
    my $temp_obj = Cpanel::TempFile->new();
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            $temp_dir = $temp_obj->dir();
            foreach my $responder ( @{$responders} ) {
                my @possible_conf_files = map { "$responder.$_" } ( 'json', 'conf' );
                foreach my $file ( $responder, @possible_conf_files ) {
                    my $file_in_source = File::Spec->catfile( $old_auto_respond_dir, $file );
                    next if !-e $file_in_source;

                    my ( $ok, $err ) = Cpanel::FileUtils::Copy::copy( $file_in_source, File::Spec->catfile( $temp_dir, $file ) );
                    $self->add_warning($err) if !$ok;
                }
            }
        },
        $from_user_uid,
        $from_user_gid
    );

    my $new_auto_respond_dir = Whostmgr::Email::Autoresponders::get_auto_responder_dir( $self->{'to_username'} );
    return $self->safesync_dirs( { 'source_dir' => $temp_dir, 'target_dir' => $new_auto_respond_dir } );
}

1;
