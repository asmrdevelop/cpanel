package Cpanel::API::GPG;

# cpanel - Cpanel/API/GPG.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::API::GPG

=head1 SYNOPSIS

    use Cpanel::Args     ();
    use Cpanel::Result   ();
    use Cpanel::API::GPG ();

    my $result = Cpanel::Result->new();
    my $args = Cpanel::Args->new( { name => 'bender is great', email => 'bender@benderisgreat.tld' } );

    Cpanel::API::GPG::generate_key( $args, $result );

    if ($result->status()) {
       # it worked
    }
    else {
       # what? of course bender is great
    }

=head1 DESCRIPTION

UAPI calls to manage a cPanel user's GPG keys.

=cut

use Cpanel::Exception ();

our $VERSION = '1.0';

my $not_allow_demo = { allow_demo => 0 };
my $allow_demo     = { allow_demo => 1 };

our %API = (
    _needs_role       => 'MailReceive',
    _needs_feature    => 'pgp',
    generate_key      => $not_allow_demo,
    list_public_keys  => $allow_demo,
    list_secret_keys  => $allow_demo,
    delete_keypair    => $not_allow_demo,
    import_key        => $not_allow_demo,
    export_public_key => $not_allow_demo,
    export_secret_key => $not_allow_demo,
);

=head1 METHODS

=head2 generate_key( $args, $result )

=head3 Purpose

Generates a GPG key with the specified options for a cpanel user.

See documentation for the C<generate_key()> method in L<Cpanel::Crypt::GPG::Generate>.

=head3 Arguments

=over 3

=item C<< name => $gpg_user_name >> [in, required]

STRING - The name of the user to associate with the key.

=item C<< email => $gpg_email >> [in, required]

STRING - The email address of the user to associate with the key.

=item C<< expire => 1560363242 >> [in, optional]

Unix timestamp - Set the expiration date of the key.

Defaults to 1 year from current date.

Cannot be used with C<no_expire>.

=item C<< no_expire => 1 >> [in, optional]

Boolean - Creates a key without an expiration date.

Cannot be used with C<expire>.

=item C<< passphrase => 'long_passphrases_are_good' >> [in, optional]

STRING - Sets the passphrase for the key.

=item C<< comment => 'a helpful comment is helpful' >> [in, optional]

STRING - Sets the comment for the key. This will be displayed when listing keys so it
can be helpful to remember what the key is used for.

=item C<< keysize => 2048 >> [in, optional]

INTEGER - Sets the keysize of the the key.

The default value is C<2048>.

=back

=head3 Returns

A string containing the output of the key generation. Usually, it is an empty string.

=cut

sub generate_key {
    my ( $args, $result ) = @_;

    my $config_hr = {};
    $config_hr->@{qw(name email)} = $args->get_length_required(qw(name email));

    # optional parameters
    $config_hr->@{qw(comment expire keysize passphrase no_expire)} = $args->get(qw(comment expire keysize passphrase no_expire));

    require Cpanel::Crypt::GPG::Generate;
    my $gpg_gen = Cpanel::Crypt::GPG::Generate->new();
    my $output  = $gpg_gen->generate_key($config_hr);
    $result->data($output);

    return 1;
}

=head2 list_public_keys()

=head3 Purpose

Lists all the public GPG keys for a cpanel user.

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
    my ( $args, $result ) = @_;

    require Cpanel::Crypt::GPG::CryptGPGFacade;
    my $obj  = Cpanel::Crypt::GPG::CryptGPGFacade->new();
    my @keys = $obj->list_public_keys();
    $result->data( \@keys );

    return 1;
}

=head2 list_secret_keys()

=head3 Purpose

Lists all the secret GPG keys for a cpanel user.

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
    my ( $args, $result ) = @_;

    require Cpanel::Crypt::GPG::CryptGPGFacade;
    my $obj  = Cpanel::Crypt::GPG::CryptGPGFacade->new();
    my @keys = $obj->list_secret_keys();
    $result->data( \@keys );

    return 1;
}

=head2 delete_keypair($args, $result)

=head3 Purpose

Delete a GPG keypair (both secret and public) for a cpanel user.

If the key we want to delete does not have a corresponding secret key (i.e.
it is a public key without a secret key), the public key will be deleted.

If the key does have a corresponding secret key, both the public
and secret key will be deleted.

=head3 Arguments

=over 3

=item C<< key_id => $keyid >> [in, required]

STRING - The ID of the GPG key to delete.

=back

=head3 Returns

Nothing.

=cut

sub delete_keypair {
    my ( $args, $result ) = @_;

    my $key_id = $args->get_length_required(qw(key_id));
    require Cpanel::Crypt::GPG::CryptGPGFacade;
    my $obj = Cpanel::Crypt::GPG::CryptGPGFacade->new();
    $obj->delete_keypair($key_id);

    return 1;
}

=head2 import_key($args, $result)

=head3 Purpose

Imports a public GPG key for a cpanel user.

=head3 Arguments

=over 3

=item C<< key_data => $key_data >> [in, required]

STRING - The public GPG key to import.

=back

=head3 Returns

A hashref with the following format:

=over 3

=item C<< key_id => 'ABCDEFGH12345678' >> [out]

STRING - The id of the GPG key.

=back

=cut

sub import_key {
    my ( $args, $result ) = @_;

    my $key_data = $args->get_length_required(qw(key_data));

    require Cpanel::Crypt::GPG::Import;
    my $obj = Cpanel::Crypt::GPG::Import->new();

    die Cpanel::Exception::create( 'Unsupported', 'Only servers with [asis,GPG] support this module.' )
      if !$obj;

    my ( $key_id, $msg ) = $obj->add_pub_key( key => $key_data );

    die Cpanel::Exception->create_raw($msg)
      if !$key_id;

    $result->data(
        {
            key_id => $key_id,
        }
    );

    return 1;
}

=head2 export_public_key($args, $result)

=head3 Purpose

Exports a GPG armored key for a cpanel user.

=head3 Arguments

=over 3

=item C<< key_id => $key_id >> [in, required]

STRING - The ID of the GPG key to export.

=back

=head3 Returns

A hashref with the following format:

=over 3

=item C<< key_data => '-----BEGIN PGP PUBLIC KEY BLOCK-----\n...-----\n' >> [out]

STRING - The exported public GPG key with newlines.

=back

=cut

sub export_public_key {
    my ( $args, $result ) = @_;

    my $key_id = $args->get_length_required(qw(key_id));

    require Cpanel::Crypt::GPG::Export;
    my $obj = Cpanel::Crypt::GPG::Export->new();

    my $data = $obj->export_public_key($key_id);

    $result->data(
        {
            key_data => $data,
        }
    );

    return 1;
}

=head2 export_secret_key($args, $result)

=head3 Purpose

Exports a secret GPG armored key for a cpanel user.

=head3 Arguments

=over 3

=item C<< key_id => $key_id >> [in, required]

STRING - The ID of the GPG key to export.

=back

=head3 Returns

A hashref with the following format:

=over 3

=item C<< key_data => '-----BEGIN PGP PRIVATE KEY BLOCK-----\n...-----\n' >> [out]

STRING - The exported secret GPG key with newlines.

=back

=cut

sub export_secret_key {
    my ( $args, $result ) = @_;

    my $key_id     = $args->get_length_required(qw(key_id));
    my $passphrase = $args->get(qw(passphrase));

    require Cpanel::Crypt::GPG::Export;
    my $obj = Cpanel::Crypt::GPG::Export->new();

    local $@;
    my $data = eval { $obj->export_secret_key( $key_id, $passphrase ) };
    if ($@) {
        my $error = $@;
        eval { $error->isa('Cpanel::Exception') } && $result->set_typed_error( ref $error );
        die $error;
    }

    $result->data(
        {
            key_data => $data,
        }
    );

    return 1;
}

1;
