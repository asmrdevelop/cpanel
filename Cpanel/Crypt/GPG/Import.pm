package Cpanel::Crypt::GPG::Import;

# cpanel - Cpanel/Crypt/GPG/Import.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Crypt::GPG::Import

=head1 SYNOPSIS

    use Cpanel::Crypt::GPG::Import ();

    my $gpg = Cpanel::Crypt::GPG::Import->new();
    $gpg->add_pub_key(key => $key);
    my ($valid, $sig) = $gpg->verify( sig => "test.file.asc", files => "test.file" );

    if ($valid) {
        print "Valid signature\nUID: $valid\nKey ID: $sig->{id}\n";
    }
    else {
        print "Invalid signature.\n";
    }

=head1 DESCRIPTION

Utilities to import and verify PGP/GPG keys and signatures.

=cut

use strict;
## no critic(RequireUseWarnings) -- This is older code and has not been tested for warnings safety yet.

use parent qw( Cpanel::Crypt::GPG::Base );

use Cpanel::SafeRun::Object ();
use Cpanel::TempFile        ();

=head1 INSTANCE METHODS

=head2 new( \%opts_hr )

=head3 Purpose

Create a new instance of this class.

=head3 Arguments

=over 3

=item C<< \%opts_hr >> [in, optional]

A hashref with optional keys to use in the module.
The currently supported keys are:

=over 3

=item C<< homedir => $path >> [in, optional]

The homedir is the folder where gpg will store key data.

=item C<< tmp => $tmp_file_obj >> [in, optional]

A C<Cpanel::TempFile> object used to store data.

=back

=back

=head3 Returns

Returns a new instance of this class.

Returns undef on failure.

=cut

sub new {
    my ( $class, $opts_hr ) = @_;

    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $self = eval { $class->SUPER::new($opts_hr) };

    if ( !$self ) {
        return wantarray ? ( undef, "Failed to find the GnuPG binary." ) : undef;
    }

    my $tmp = ( $opts_hr->{tmp} ) ? $opts_hr->{tmp} : Cpanel::TempFile->new();
    $self->{tmp} = $tmp;

    return $self;
}

=head2 verify( %args )

=head3 Purpose

Verify a detached signature against file.

=head3 Arguments

=over 3

=item C<< %args >> [in, required]

A hash with the following keys:

=over 3

=item C<< sig => $path_to_sig >> [in, required]

Path to signature.
Either this or C<sig_data> must be specified.

=item C<< sig_data => $signature_data >> [in, required]

Raw signature data, could be a string or binary data.
Either this or C<sig> must be specified.

=item C<< files => $files >> [in, required]

Path to files.
Can be a scalar value for a singular file. Or an array reference for multiple.
Either this or C<files_data> must be specified.

=item C<< files_data => $files_data >> [in, required]

Raw files data.
Can be a scalar value for a singular file. Or an array reference for multiple.
Either this or C<files> must be specified.

=back

=back

=head3 Returns

In scalar context returns a hashref. If reference is undefined, an error is indicated.
In list context returns a list containing C<($hashref, $error_message)>.

The hashref in the two above referenced scenarios will contain the following keys:

    id => Public key ID for the signature.
    create_time => Creation time of the signature (in seconds since the epoch).
    expire_time => Expiration time of the signature (in seconds since the epoch).

=cut

sub verify {
    my ( $self, %args ) = @_;
    my ( $sig, @files );

    if ( $args{sig} ) {
        $sig = $args{sig};
    }
    elsif ( $args{sig_data} ) {
        $sig = $self->_write_data_to_temp_file( $args{sig_data}, $self->{tmp} );
    }
    else {
        return wantarray ? ( undef, "Arguments 'sig' or 'sig_data' must be provided." ) : undef;
    }

    # It is possible that 'files_data' be defined but 0 bytes.

    if ( $args{files} ) {
        @files = ( ref( $args{files} ) eq 'ARRAY' ) ? @{ $args{files} } : ( $args{files} );
    }
    elsif ( defined( $args{files_data} ) ) {
        for my $file ( ( ref( $args{files_data} ) eq 'ARRAY' ) ? @{ $args{files_data} } : ( $args{files_data} ) ) {
            push @files, $self->_write_data_to_temp_file( $file, $self->{tmp} );
        }
    }
    else {
        return wantarray ? ( undef, "Arguments 'files' or 'files_data' must be provided." ) : undef;
    }

    my @args = (
        '--logger-fd', '1',
        '--status-fd', '1',
        $self->{homedir} ? ( '--homedir' => $self->{homedir} ) : (),
        '--verify', $sig,
        @files,
    );

    my $run = Cpanel::SafeRun::Object->new(
        program => $self->{bin},
        args    => \@args,
        timeout => _gpg_timeout(),
    );

    if ( !$run ) {
        return wantarray ? ( undef, "Failed to invoke gpg." ) : undef;
    }

    my $sig_data = undef;
    my $status   = "Failed to validate signature due to some unknown error.";

    my %notes;
    my $curnote;

    # Information on these return values can be found in 'doc/DETAILS' in the GnuPG source.

    for my $l ( split /\n/, $run->stdout() ) {
        if ( $l =~ /^\[GNUPG:\] VALIDSIG ([A-F0-9]+) (\d+-\d+-\d+) (\d+) ([A-F0-9]+) ([A-F0-9]+) ([A-F0-9]+) ([A-F0-9]+) ([A-F0-9]+) ([A-F0-9]+) ([A-F0-9]+)$/ ) {
            $sig_data = {
                id          => substr( $1, -16 ),
                create_time => $3,
                expire_time => $4,
            };

            $status = "Valid signature.";
        }
        elsif ( $l =~ /^\[GNUPG:\] BADSIG ([A-F0-9]+) (.+)$/ ) {
            $status = "Invalid signature.";
        }
        elsif ( $l =~ /^\[GNUPG:\] NO_PUBKEY ([A-F0-9]+)$/ ) {
            $status = "Could not find public key in keychain.";
        }
        elsif ( $l =~ /^\[GNUPG:\] NODATA ([A-F0-9]+)$/ ) {
            $status = "Could not find a GnuPG signature in the signature file.";
        }
        elsif ( $l =~ /^\[GNUPG:\] NOTATION_NAME (.+)$/ ) {
            $curnote = $1;
            $notes{$curnote} = '';
        }
        elsif ( $l =~ /^\[GNUPG:\] NOTATION_DATA (.+)$/ ) {
            $notes{$curnote} .= $1;
        }
    }

    # Patch in notations if we got a valid signature.

    if ($sig_data) {
        $sig_data->{notations} = \%notes;
    }

    return wantarray ? ( $sig_data, "$status (@files)" ) : $sig_data;
}

=head2 add_pub_key( %args )

=head3 Purpose

Adds an ascii-armored public key to the public keychain.

=head3 Arguments

=over 3

=item C<< %args >> [in, required]

A hash with the following keys:

=over 3

=item C<< key => $key >> [in, required]

A string containing the ASCII armored public key.

=back

=back

=head3 Returns

In scalar context returns the key id indicating success.
In list context returns a list containing C<($id, $status_message)>.

=cut

sub add_pub_key {
    my ( $self, %args ) = @_;

    if ( !$args{key} ) {
        return wantarray ? ( undef, "No key provided." ) : undef;
    }

    my @args = (
        '--logger-fd', '1',
        '--status-fd', '1',
        $self->{homedir} ? ( '--homedir' => $self->{homedir} ) : (),
        '--import'
    );

    my $run = Cpanel::SafeRun::Object->new(
        program => $self->{bin},
        args    => \@args,
        stdin   => $args{key},
        timeout => _gpg_timeout(),
    );

    if ( !$run ) {
        return wantarray ? ( undef, "Failed to invoke gpg." ) : undef;
    }

    my @r = ( undef, "Failed to import key." );

    for my $l ( split /\n/, $run->stdout() ) {
        if ( $l =~ /^\[GNUPG:\] IMPORT_OK \d+ ([A-F0-9]+)$/ ) {
            my $id = substr( $1, -16 );
            @r = ( $id, "Successfully imported key." );
        }
    }

    return wantarray ? @r : shift @r;
}

=head2 get_key_id( %args )

=head3 Purpose

Unpacks and parses an ASCII armored key.

=head3 Arguments

=over 3

=item C<< %args >> [in, required]

A hash with the following keys:

=over 3

=item C<< key => $key >> [in, required]

A scalar string containg ASCII armored the key data.

=back

=back

=head3 Returns

Returns scalar string containing the hex representation of the key ID.
Returns undef on failure.

=cut

sub get_key_id {
    my ( $self, %args ) = @_;

    if ( !$args{key} ) {
        return wantarray ? ( undef, "No key provided." ) : undef;
    }

    my @r = ( undef, "Failed to parse key id." );

    if ( my $id = $self->add_pub_key(%args) ) {
        @r = ( $id, "Successfully parsed key id." );
    }

    return wantarray ? @r : shift @r;
}

=head2 _write_data_to_temp_file( $data )

=head3 Purpose

Writes data out to a temporary file.

=head3 Arguments

=over 3

=item C<< $data >> [in, required]

The string data to write to the C<Cpanel::TempFile> object.

=back

=head3 Returns

Returns filename.

=cut

sub _write_data_to_temp_file {
    my ( $self, $data )   = @_;
    my ( $name, $handle ) = $self->{tmp}->file();

    binmode $handle;    # We may be opening binary OpenPGP data.
    print {$handle} $data;
    close($handle);

    return $name;
}

=head2 _gpg_timeout()

=head3 Purpose

Provides the timeout (in seconds) for calls to gpg.

=head3 Returns

Returns a number.

=cut

sub _gpg_timeout {
    return 60;
}

1;
