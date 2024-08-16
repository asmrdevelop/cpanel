package Cpanel::Crypt::GPG::CryptGPGFacade;

# cpanel - Cpanel/Crypt/GPG/CryptGPGFacade.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Crypt::GPG::CryptGPGFacade

=head1 SYNOPSIS

    use Cpanel::Crypt::GPG::CryptGPGFacade ();

    my $gpg = Cpanel::Crypt::GPG::CryptGPGFacade->new();
    my @pub_keys = $gpg->list_public_keys();
    my @sec_keys = $gpg->list_secret_keys();

=head1 DESCRIPTION

Provides a wrapper around the Crypt::GPG module to work with GPG keys.

=cut

use parent qw (Cpanel::Crypt::GPG::Base);

use Crypt::GPG              ();
use Cpanel::Exception       ();
use Cpanel::SafeRun::Simple ();

use Try::Tiny;

# See https://tools.ietf.org/html/rfc4880#section-9.1 and https://tools.ietf.org/html/rfc6637#page-4
my %algorithm_lookup = (
    1   => 'RSA (Encrypt or Sign)',
    2   => 'RSA Encrypt-Only',
    3   => 'RSA Sign-Only',
    16  => 'Elgamal (Encrypt-Only)',
    17  => 'DSA',
    18  => 'ECDH public key algorithm',
    19  => 'ECDSA public key algorithm',
    20  => 'Reserved (formerly Elgamal Encrypt or Sign)',
    21  => 'Reserved for Diffie-Hellman (X9.42, as defined for IETF-S/MIME)',
    100 => 'Private/Experimental algorithm',
    101 => 'Private/Experimental algorithm',
    102 => 'Private/Experimental algorithm',
    103 => 'Private/Experimental algorithm',
    104 => 'Private/Experimental algorithm',
    105 => 'Private/Experimental algorithm',
    106 => 'Private/Experimental algorithm',
    107 => 'Private/Experimental algorithm',
    108 => 'Private/Experimental algorithm',
    109 => 'Private/Experimental algorithm',
    110 => 'Private/Experimental algorithm',
);

=head1 INSTANCE METHODS

=head2 new( \%opts_hr )

=head3 Purpose

Creates an object of this class.

=head3 Arguments

=over 3

=item C<< \%opts_hr >> [in, optional]

A hashref with optional keys to use in the module.

=back

=head3 Returns

An instance of this class.

=head3 Throws

=over 3

=item When GPG cannot be found on the system

=back

=cut

sub new {
    my ( $class, $opts_hr ) = @_;

    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $self = $class->SUPER::new($opts_hr);

    my $gpg = Crypt::GPG->new();
    $gpg->gpgbin( $self->get_gpg_bin() );
    $gpg->gpgopts('--lock-multiple');    # Set on advice of perldoc for Crypt::GPG module

    $self->{'gpg_obj'}   = $gpg;
    $self->{'key_cache'} = [];

    return $self;
}

=head2 list_public_keys

=head3 Purpose

Lists all the public GPG keys for a user.

The user is determined by who is calling this module.

=head3 Arguments

None

=head3 Returns

An array (list) of hash references consisting of the public keys for the user in the following format:

=over 3

=item C<< algorithm => 'DSA' >> [out]

STRING - The algorithm of the GPG key.

=item C<< bits => '1024' >> [out]

STRING - The length of the GPG key in bits.

=item C<< created => '1556924286' >> [out]

Unix timestamp - The date the GPG key was created.

=item C<< expires => '1588460286' >> [out]

Unix timestamp - The date the GPG key expires.

=item C<< id => 'C8025780A3DAA1C3' >> [out]

STRING - The id of the GPG key.

=item C<< type => 'pub' >> [out]

STRING - The type of GPG key, either pub (for public) or sec (for secret).

=item C<< user_id => 'heyyo (comment) <bender@benderisgreat.tld>' >> [out]

STRING - A string consisting of the name, comment, and email address associated
with the GPG key.

=back

=cut

sub list_public_keys {
    my $self = shift;
    my @keys = $self->_list_keys();
    return map {
        {
            'created'   => $_->{'Created'},
            'expires'   => $_->{'Expires'},
            'user_id'   => ( defined $_->{'UIDs'}->[0]->{'UID'} ) ? $_->{'UIDs'}->[0]->{'UID'} : '',    # just get the first one if available
            'bits'      => $_->{'Bits'},
            'id'        => $_->{'ID'},
            'type'      => $_->{'Type'},
            'algorithm' => scalar _get_algorithm_name( $_->{'Algorithm'} ),
        }
    } grep { $_->{'Type'} eq 'pub' } @keys;
}

=head2 list_secret_keys

=head3 Purpose

Lists all the secret GPG keys for a user.

The user is determined by who is calling this module.

=head3 Arguments

None

=head3 Returns

An array (list) of hash references consisting of the public keys for the user in the following format:

=over 3

=item C<< algorithm => 'DSA' >> [out]

STRING - The algorithm of the GPG key.

=item C<< bits => '1024' >> [out]

STRING - The length of the GPG key in bits.

=item C<< created => '1556924286' >> [out]

Unix timestamp - The date the GPG key was created.

=item C<< expires => '1588460286' >> [out]

Unix timestamp - The date the GPG key expires.

=item C<< id => 'C8025780A3DAA1C3' >> [out]

STRING - The id of the GPG key.

=item C<< type => 'sec' >> [out]

STRING - The type of GPG key, either pub (for public) or sec (for secret).

=item C<< user_id => 'heyyo (comment) <bender@benderisgreat.tld>' >> [out]

STRING - A string consisting of the name, comment, and email address associated
with the GPG key.

=back

=cut

sub list_secret_keys {
    my $self = shift;
    my @keys = $self->_list_keys();
    return map {
        {
            'created'   => $_->{'Created'},
            'expires'   => $_->{'Expires'},
            'user_id'   => ( defined $_->{'UIDs'}->[0]->{'UID'} ) ? $_->{'UIDs'}->[0]->{'UID'} : '',    # just get the first one if available
            'bits'      => $_->{'Bits'},
            'id'        => $_->{'ID'},
            'type'      => $_->{'Type'},
            'algorithm' => scalar _get_algorithm_name( $_->{'Algorithm'} ),
        }
    } grep { $_->{'Type'} eq 'sec' } @keys;
}

sub _list_keys {
    my ($self) = @_;

    # use the cache if possible
    if ( $self->{'key_cache'} && scalar @{ $self->{'key_cache'} } ) {
        return @{ $self->{'key_cache'} };
    }

    # NOTE: If something goes wrong, Crypt::GPG returns undef. So we cannot really
    # tell the difference between something going wrong or the user not having any keys.
    my @keys = $self->{'gpg_obj'}->keydb();
    $self->{'key_cache'} = \@keys;
    return @keys;
}

=head2 delete_keypair( $key_id )

=head3 Purpose

Delete a GPG keypair (both secret and public) from the user's key ring.

A keypair consists of a public and a secret GPG key. Both the secret and public
GPG keys share the same key id.

If a key id is passed and does not have a corresponding secret key, the public
key will be deleted.

If a key id is passed and does have a corresponding secret key, both the public
and secret key will be deleted.

=head3 Arguments

=over 3

=item C<< $key >> [in, required]

A string containing the ID of the GPG key.

=back

=head3 Returns

Returns 1 if the key was deleted successfully.

=head3 Throws

=over 3

=item When a key is not passed in

=item When GPG cannot be found on the system

=item When the key passed in could not be found

=item When the system fails to delete the GPG key

=back

=cut

sub delete_keypair {
    my ( $self, $key_id ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['key_id'] )
      if !defined $key_id;

    my @keys  = $self->_list_keys();
    my @found = grep { $_->{'ID'} eq $key_id && ( $_->{'Type'} eq 'pub' || $_->{'Type'} eq 'sec' ) } @keys;

    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The [asis,GPG] key “[_1]” could not be found.', [$key_id] )
      if !scalar @found;

    # first, we try deleting the key pair using the module, which may not be compatible
    # with newer versions of GPG.

    # See if we have a secret key
    my @sec_found = grep { $_->{'Type'} eq 'sec' } @found;
    if ( scalar @sec_found ) {
        try { $self->{'gpg_obj'}->delkey( $sec_found[0] ) };
    }
    else {
        try { $self->{'gpg_obj'}->delkey( $found[0] ) };
    }

    $self->_clear_key_cache();
    @keys  = $self->_list_keys();
    @found = grep { $_->{'ID'} eq $key_id && ( $_->{'Type'} eq 'pub' || $_->{'Type'} eq 'sec' ) } @keys;

    return 1 unless scalar @found;

    # first effort failed, now try deleting the key pair directly
    # See if we have a secret key
    @sec_found = grep { $_->{'Type'} eq 'sec' } @found;

    # See if we have a public key
    my @pub_found = grep { $_->{'Type'} eq 'pub' } @found;

    # If we have a secret key, we need to delete the secret key first, then the public key
    my $result;
    if ( scalar @sec_found ) {
        $result = $self->_delete_sec_key( $sec_found[0] );
        die Cpanel::Exception->create( 'The system failed to delete the secret [asis,GPG] key “[_1]”.', [$key_id] )
          if !$result;
    }

    if ( scalar @pub_found ) {
        $result = $self->_delete_pub_key( $pub_found[0] );
        die Cpanel::Exception->create( 'The system failed to delete the public [asis,GPG] key “[_1]”.', [$key_id] )
          if !$result;
    }

    $self->_clear_key_cache();

    return 1;
}

sub _delete_sec_key {
    my ( $self, $key ) = @_;

    my $gpgbin = $self->get_gpg_bin();
    my $key_id = $key->{'ID'};

    my $rout       = Cpanel::SafeRun::Simple::saferunnoerror( $gpgbin, '--list-secret-keys' );
    my @signatures = grep /$key_id/, split( /\n/, $rout );

    if ( $signatures[0] ) {
        $rout = Cpanel::SafeRun::Simple::saferunonlyerrors( $gpgbin, '--batch', '--yes', '--delete-secret-keys', $signatures[0] );
        return 0 if $rout;
    }

    return 1;
}

sub _delete_pub_key {
    my ( $self, $key ) = @_;

    my $gpgbin = $self->get_gpg_bin();
    my $key_id = $key->{'ID'};

    my $rout = Cpanel::SafeRun::Simple::saferunonlyerrors( $gpgbin, '--batch', '--yes', '--delete-keys', $key_id );
    return 0 if $rout;

    return 1;
}

sub _clear_key_cache {
    my $self = shift;
    $self->{'key_cache'} = [];
    return;
}

sub _get_algorithm_name {
    my $algo_num = shift;
    return '' if !defined $algo_num;
    return $algorithm_lookup{$algo_num} // '';
}

1;
