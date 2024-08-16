package Cpanel::DKIM::Save;

# cpanel - Cpanel/DKIM/Save.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Save

=head1 SYNOPSIS

    Cpanel::DKIM::Save::save( 'example.com', $private_key_pem );

=head1 DESCRIPTION

This module contains logic to save DKIM keys on disk.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie          ();
use Cpanel::DKIM::Load       ();
use Cpanel::FileUtils::Write ();

my $DKIM_PUBLIC_KEY_PERMISSIONS  = 0644;
my $DKIM_PRIVATE_KEY_PERMISSIONS = 0640;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 save( $DOMAIN, $PRIVATE_KEY_PEM )

Save $DOMAIN’s DKIM key $PRIVATE_KEY_PEM to the datastore.
Throws a suitable exception on failure.

NB: This interface may change in the future to require a username.
If you add a new call to this function, try to make the username
available in the same context that calls this function. This will
minimize the disruption from the anticipated interface change.

=cut

sub save {
    my ( $domain, $key_pem ) = @_;

    # Rudimentary validation that $key_pem is a valid RSA key:
    my $public_pem = _get_public_pem($key_pem);

    # TODO: This would more ideally work thus:
    # /var/cpanel/domain_keys/$domain is a symlink to a directory,
    # and that directory is where the public & private keys are stored.
    # Then the installation of public & private would be transactional:
    # either both would succeed, or both would fail.
    #
    # The approach below gets us close: the private and public keys are
    # at least both written and ready-to-rock before they’re “installed”.
    # But we could still get a case where the installation of one fails
    # while the other succeeds.

    _save_domain_private_key(
        $key_pem, $domain,
        sub {
            _save_domain_public_key( $public_pem, $domain );
        }
    );

    _schedule_propagation_if_needed($domain);

    return;
}

sub _schedule_propagation_if_needed ( $domain, $username = undef ) {

    require Cpanel::DKIM::Propagate;

    warn if !eval {
        if ($username) {
            Cpanel::DKIM::Propagate::schedule_propagation_for_user_if_needed( $username, $domain );
        }
        else {
            Cpanel::DKIM::Propagate::schedule_propagation_if_needed($domain);
        }

        1;
    };

    return;
}

#----------------------------------------------------------------------

=head2 $deleted_yn = delete( $DOMAIN, $USERNAME )

Deletes $DOMAIN’s DKIM key from the datastore on $USERNAME’s behalf.
Returns truthy if something was deleted or falsy if there was
nothing to delete. Throws a suitable exception on failure.

=cut

sub delete ( $domain, $username ) {

    my $private = _get_key_path( 'private', $domain );

    my $deleted = Cpanel::Autodie::unlink_if_exists($private);

    if ($deleted) {
        _schedule_propagation_if_needed( $domain, $username );
    }

    my $public = _get_key_path( 'public', $domain );

    # Failure to delete the public key file isn’t fatal
    # because this file is just a cache.
    require Cpanel::Autowarn;
    Cpanel::Autowarn::unlink($public);

    return $deleted;
}

#----------------------------------------------------------------------

sub _get_public_pem {
    my ($key_pem) = @_;

    require Crypt::OpenSSL::RSA;

    my $key_obj = Crypt::OpenSSL::RSA->new_private_key($key_pem);

    return $key_obj->get_public_key_x509_string();
}

#Pass in either a scalar or a scalar ref for the key.
sub _save_domain_public_key {
    my ( $key, $domain ) = @_;

    return _save_key_type_for_domain( $key, 'public', $domain, $DKIM_PUBLIC_KEY_PERMISSIONS );
}

#Pass in either a scalar or a scalar ref for the key.
sub _save_domain_private_key {
    my ( $key, $domain, $todo_cr ) = @_;

    my $fh = _save_key_type_for_domain(
        $key,
        'private',
        $domain,
        {
            before_installation => sub {
                my ($fh) = @_;

                _prepare_private_key_fh($fh);

                $todo_cr->();
            },
        },
    );

    return;
}

my $mail_gid;

sub _prepare_private_key_fh {
    my ($fh) = @_;

    $mail_gid ||= getgrnam 'mail' || die 'Found no “mail” group??';

    Cpanel::Autodie::chown( -1, $mail_gid, $fh );

    Cpanel::Autodie::chmod( $DKIM_PRIVATE_KEY_PERMISSIONS, $fh );

    return;
}

sub _save_key_type_for_domain {
    my ( $key_text, $type, $domain, $perms_or_hr ) = @_;

    my $path = _get_key_path( $type, $domain );

    # No transaction needed here because overwrite does rename in place
    return Cpanel::FileUtils::Write::overwrite( $path, ref $key_text ? $$key_text : $key_text, $perms_or_hr );
}

*_get_key_path = *Cpanel::DKIM::Load::get_key_path;

1;
