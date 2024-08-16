package Cpanel::SSL::Hostname::Update;

# cpanel - Cpanel/SSL/Hostname/Update.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Hostname::Update

=head1 SYNOPSIS

    my $num_updated = Cpanel::SSL::Hostname::Update::update_apache_installations(
        $old_crt_obj,
        $new_crt_obj,
    );

=cut

#----------------------------------------------------------------------
use Try::Tiny;

use Cpanel::Imports;

# This module is unshipped, so we need to compile it in.
use Cpanel::DomainIp   ();
use Cpanel::SSLInstall ();

use Cpanel::SSLStorage::Utils ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $updates_count = update_apache_installations( $OLD_OBJ, $NEW_OBJ )

This takes two L<Cpanel::SSL::Objects::Certificate> instances. If they’re
not for the same underlying certificate, then it queries Apache TLS
(cf. L<Cpanel::Apache::TLS::Index>) to see if $OLD_OBJ’s certificate is
installed anywhere in Apache.

For any such vhosts, this will install the new certificate. (This
installation will propagate to Domain TLS as well.)

This doesn’t throw any exceptions, but any errors that happen internally
prompt warnings.

The return value is the number of updated Apache vhosts.

=cut

sub update_apache_installations {
    my ( $old_crt_obj, $new_crt_obj ) = @_;

    # sanity check
    for my $crt_obj ( $old_crt_obj, $new_crt_obj ) {
        if ( !try { $crt_obj->isa('Cpanel::SSL::Objects::Certificate') } ) {
            die "Need certificate object, not “$crt_obj”";
        }
    }

    my $old_id = Cpanel::SSLStorage::Utils::make_certificate_id($old_crt_obj);
    my $new_id = Cpanel::SSLStorage::Utils::make_certificate_id($new_crt_obj);

    my $number_of_updated_vhosts = 0;

    if ( $old_id eq $new_id ) {
        print locale()->maketext('The new certificate is the same certificate as the previous one.') . "\n";
    }
    else {
        my $key_pem;

        try {
            require Cpanel::Apache::TLS::Index;
            my $atls_idx = Cpanel::Apache::TLS::Index->new();

            my @atls_records = $atls_idx->get_for_certificate_id($old_id);

            if (@atls_records) {
                my @vhost_names = map { $_->{'vhost_name'} } @atls_records;

                print locale()->maketext( 'Updating [asis,SSL] for [quant,_1,Apache virtual host,Apache virtual hosts] ([list_and_quoted,_2]) …', 0 + @vhost_names, \@vhost_names ) . "\n";

                # To install the new certificate we have to have the
                # certificate’s key, which we can get from SSLStorage.
                #
                # NB: We don’t bother with the CA bundle here because the
                # installer can just fetch it from the certificate’s
                # caIssuers URL.

                require Cpanel::SSLStorage::User;
                my $sslstorage = Cpanel::SSLStorage::User->new();

                my ( $ok, $resp_or_err ) = $sslstorage->find_keys(
                    map { $_ => $new_crt_obj->$_() } (
                        'key_algorithm',
                        'modulus',
                        'ecdsa_curve_name',
                        'ecdsa_public',
                    )
                );
                die $resp_or_err if !$ok;

                ( $ok, my $pem_or_err ) = $sslstorage->get_key_text( $resp_or_err->[0]{'id'} );
                die $pem_or_err if !$ok;

                $key_pem = $pem_or_err;
            }

            for my $rec (@atls_records) {
                try {
                    require Whostmgr::ACLS;

                    #Needed for Cpanel::SSLInstall to be happy.
                    local $ENV{'REMOTE_USER'} = 'root';
                    local %Whostmgr::ACLS::ACL;
                    Whostmgr::ACLS::init_acls();

                    my $install = Cpanel::SSLInstall::real_installssl(
                        domain => $rec->{'vhost_name'},
                        crt    => $new_crt_obj->text(),
                        key    => $key_pem,

                        # This is needed in case “nobody” owns the SSL
                        # vhost to be updated. That user’s non-SSL
                        # vhost’s userdata has “*” as an IP address.
                        ip => scalar( Cpanel::DomainIp::getdomainip( $rec->{'vhost_name'} ) ),

                        # No “cab” is needed because the installer will
                        # just fetch it from the certificate’s caIssuers URL.
                    );

                    if ( $install->{'status'} ) {
                        $number_of_updated_vhosts++;

                        print locale()->maketext( 'The system updated “[_1]”’s web virtual host.', $rec->{'vhost_name'} ) . "\n";
                    }
                    else {
                        die $install->{'message'};
                    }
                }
                catch {
                    warn "Failed to update Apache installation of hostname certificate on “$rec->{'vhost_name'}”: $_";
                };
            }
        }
        catch {
            local $@ = $_;
            warn;
        };
    }

    return $number_of_updated_vhosts;
}

1;
