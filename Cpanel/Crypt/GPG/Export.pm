package Cpanel::Crypt::GPG::Export;

# cpanel - Cpanel/Crypt/GPG/Export.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Crypt::GPG::Export

=head1 SYNOPSIS

    use Cpanel::Crypt::GPG::Export ();
    my $gpg = Cpanel::Crypt::GPG::Export->new();
    my $result = $gpg->export_public_key( 'ABCDEFGHIJKLMNOP' );

=head1 DESCRIPTION

Provide functionality to export armored GPG keys.

=cut

use parent qw( Cpanel::Crypt::GPG::Base );

use Cpanel::Exception       ();
use Cpanel::SafeRun::Object ();

use Cpanel::FastSpawn::InOut ();

=head1 INSTANCE METHODS

=head2 export_public_key( $key_id )

=head3 Purpose

Exports an armored GPG public key with the provided key id.

=head3 Arguments

=over 3

=item C<< $key_id >> [in, required]

The id of the GPG key to export.
Expected to be 8 or 16 characters long.

=back

=head3 Returns

A string containing the output of the key export.

=head3 Throws

=over 3

=item When parameters are invalid

=item When GPG cannot be found on the system

=item When GPG key cannot be found

=back

=cut

sub export_public_key {
    my ( $self, $key_id ) = @_;
    return $self->_export( $key_id, 0 );
}

=head2 export_secret_key( $key_id )

=head3 Purpose

Exports an armored GPG secret key with the provided key id.

=head3 Arguments

=over 3

=item C<< $key_id >> [in, required]

The id of the GPG key to export.
Expected to be 8 or 16 characters long.

=back

=head3 Returns

A string containing the output of the key export.

=head3 Throws

=over 3

=item When parameters are invalid

=item When GPG cannot be found on the system

=item When GPG key cannot be found

=back

=cut

sub export_secret_key {
    my ( $self, $key_id, $passphrase ) = @_;
    return $self->_export( $key_id, 1, $passphrase );
}

=head1 PRIVATE METHODS

=head2 _export( $key_id, $secret )

=head3 Purpose

The actual workhorse that exports the GPG key.

=head3 Arguments

=over 3

=item C<< $key_id >> [in, required]

The id of the GPG key to export.
Expected to be 8 or 16 characters long.

=item C<< $secret >> [in, required]

A boolean. 1 to export a secret key, 0 for public key.

=back

=head3 Returns

A string containing the output of the key export.

=head3 Throws

=over 3

=item When parameters are invalid

=item When GPG cannot be found on the system

=item When GPG key cannot be found

=back

=cut

sub _export {
    my ( $self, $key_id, $secret, $passphrase ) = @_;

    my $gpg_bin = $self->get_gpg_bin();
    _validate_key_id($key_id);

    my $export_run = Cpanel::SafeRun::Object->new(
        program => $gpg_bin,
        args    => [
            $self->{homedir} ? ( '--homedir' => $self->{homedir} ) : (),
            '--no-secmem-warning',
            '-a',
            $secret ? ('--export-secret-keys') : ('--export'),
            $key_id,
        ],
    );

    my $stdout = $export_run->stdout();
    return $stdout if length $stdout;

    unless ( $secret && $passphrase ) {
        my $stderr = $export_run->stderr();
        if ( $secret && $stderr && $stderr =~ m/Inappropriate ioctl for device/ ) {
            die Cpanel::Exception::create( 'GPG::PassphraseRequired', 'The secret key requires a passphrase.' );
        }

        # If the output is empty, assume that it failed
        die Cpanel::Exception->create( 'The system failed to export the [asis,GPG] key “[_1]”.', [$key_id] );
    }

    return $self->_export_sec_key_with_passphrase( $key_id, $passphrase );
}

=head2 _export_sec_key_with_passphrase( $key_id, $passphrase )

=head3 Purpose

Exports secret key secured with a passphrase.

=head3 Arguments

=over 3

=item C<< $key_id >> [in, required]

The id of the GPG key.

=item C<< $passphrase >> [in, required]

The passphrase for the GPG key.

=back

=head3 Returns

A string containing the output of the key export.

=head3 Throws

=over 3

=item When export of the key yields no result.

=back

=cut

sub _export_sec_key_with_passphrase {
    my ( $self, $key_id, $passphrase ) = @_;
    my $gpg_bin = $self->get_gpg_bin();

    my ( $w_fh, $r_fh, $e_fh );

    my $pid = Cpanel::FastSpawn::InOut::inout_all(
        stdin   => \$w_fh,
        stdout  => \$r_fh,
        stderr  => \$e_fh,
        program => $gpg_bin,
        args    => [
            '--passphrase-fd', '0',
            '--pinentry-mode', 'loopback',
            '--no-secmem-warning',
            '-a',
            '--export-secret-keys',
            $key_id,
        ],
    );
    my ( $res, $err );
    if ($pid) {
        print {$w_fh} $passphrase, "\n";
        close($w_fh);

        {
            local $/;
            $res = readline($r_fh);
            $err = readline($e_fh);
        }

        close($r_fh);
        close($e_fh);
        waitpid( $pid, 0 );
    }

    # If the output is empty, assume that it failed
    if ( !length $res ) {
        die Cpanel::Exception::create( 'GPG::IncorrectPassphrase', 'The passphrase provided was incorrect.' ) if $err =~ m/Bad passphrase/;
        die Cpanel::Exception->create( 'The system failed to export the [asis,GPG] key “[_1]”.', [$key_id] );
    }

    return $res;
}

=head2 _validate_key_id( $key_id )

=head3 Purpose

Basic validation of a GPG key id.

The key id format depends on how the list of keys is generated.

The key id is a string consisting of hexadecimal characters.

When using --with-colons, the key id is 16 chars long (key fingerprint first 8 chars and key id is second 8 chars).

When not using --with-colons, the key id is just 8 chars.

See L<https://git.gnupg.org/cgi-bin/gitweb.cgi?p=gnupg.git;a=blob_plain;f=doc/DETAILS;hb=refs/heads/master> for more information.

=head3 Arguments

=over 3

=item C<< $key_id >> [in, required]

The id of the GPG key.

=back

=head3 Returns

Nothing.

=head3 Throws

=over 3

=item When passed an undef key

=item When the GPG key is not 8 or 16 characters long

=back

=cut

sub _validate_key_id {
    my ($id) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'key_id' ] )
      if !$id;

    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must either be [quant,_2,character,characters] or [quant,_3,character,characters] long.', [ 'key_id', 8, 16 ] )
      if !( length $id == 8 || length $id == 16 );
    return 1;
}

1;
