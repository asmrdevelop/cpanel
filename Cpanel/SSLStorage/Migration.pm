package Cpanel::SSLStorage::Migration;

# cpanel - Cpanel/SSLStorage/Migration.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::LoadFile                     ();
use Cpanel::Locale                       ();
use Cpanel::PwCache                      ();
use Cpanel::SafeDir::Read                ();
use Cpanel::SSLStorage::User             ();

my $locale;

#Returns two or three items:
#   On failure: 0, <message>
#   On success: 1, {
#       filename => { type => "...", file_path => <full path> },
#       filename2 => ...,
#   },
#   [ non-fatal warning messages ]
sub homedir_to_sslstorage {
    my ($user) = @_;

    my @warning_messages = ();
    my $homedir          = Cpanel::PwCache::gethomedir($user);

    my %_read_dir_cache;    ## crt, cab, and csr read the same directory
    my %homedir_ssl_files_to_copy;

    my %valid_file_regex = ( 'key' => qr/\.key$/, 'crt' => qr/\.crt$/, 'csr' => qr/\.csr$/ );
    my @ssl_file_types   = qw( key crt csr );
    for my $ssl_file_type (@ssl_file_types) {

        my $filedir = ( $ssl_file_type eq 'key' ) ? "$homedir/ssl/private" : "$homedir/ssl/certs";

        unless ( exists $_read_dir_cache{$filedir} ) {
            $_read_dir_cache{$filedir} = Cpanel::SafeDir::Read::read_dir($filedir);
        }
        my $homedir_ssl_files_ref = $_read_dir_cache{$filedir};

        for my $homedir_ssl_fname ( @{$homedir_ssl_files_ref} ) {
            if ( $homedir_ssl_fname =~ $valid_file_regex{$ssl_file_type} && !exists $homedir_ssl_files_to_copy{$homedir_ssl_fname} ) {
                $homedir_ssl_files_to_copy{$homedir_ssl_fname} = {
                    'type'      => $ssl_file_type,
                    'file_path' => "$filedir/$homedir_ssl_fname",
                };
            }
        }
    }

    # move the ssl files already in the user's directory to the new location
    if ( keys %homedir_ssl_files_to_copy ) {
        my $copyfiles_coderef = sub {
            my ( $ok, $user_ssl_storage ) = Cpanel::SSLStorage::User->new( user => $user );
            if ( !$ok ) {
                $locale ||= Cpanel::Locale->get_handle();
                return ( 0, $locale->maketext( 'SSL datastore initialization for “[_1]” failed because of an error: [_2]', $user, $user_ssl_storage ) );
            }
            while ( my ( $src_file, $file_info ) = each %homedir_ssl_files_to_copy ) {
                ## in case the ssl file has been removed by the user while this runs
                next if ( !-e $file_info->{'file_path'} );

                my $file_contents = Cpanel::LoadFile::loadfile( $file_info->{'file_path'} );
                if ( !$file_contents ) {
                    $locale ||= Cpanel::Locale->get_handle();
                    push @warning_messages, $locale->maketext( 'An error prevented the file “[_1]” from being loaded: [_2]', $file_info->{'file_path'}, $! );
                    next;
                }

                my $type      = $file_info->{'type'};
                my $ext_regex = $valid_file_regex{$type};

                my $friendly_name = $src_file;
                $friendly_name =~ s{$ext_regex}{};

                my %args = (
                    'text'          => $file_contents,
                    'friendly_name' => $friendly_name,
                );

                my ( $status, $return_ref );
                if ( $type eq 'key' ) {
                    ( $status, $return_ref ) = $user_ssl_storage->add_key(%args);
                }
                elsif ( $type eq 'crt' ) {
                    ( $status, $return_ref ) = $user_ssl_storage->add_certificate(%args);
                }
                elsif ( $type eq 'csr' ) {
                    ( $status, $return_ref ) = $user_ssl_storage->add_csr(%args);
                }
                else {
                    return ( 0, "Invalid type: $type" );    #Implementor error
                }

                if ( !$status ) {
                    $locale ||= Cpanel::Locale->get_handle();
                    push @warning_messages, $locale->maketext( 'An error prevented adding a record of type “[_1]” ([_2]) to the SSL datastore for the user “[_3]”: [_4]', $type, $file_info->{'file_path'}, $user, $return_ref );
                    next;
                }
            }

            return 1;
        };
        Cpanel::AccessIds::ReducedPrivileges::call_as_user( $copyfiles_coderef, $user );
    }

    return ( 1, \%homedir_ssl_files_to_copy, \@warning_messages );
}

1;
