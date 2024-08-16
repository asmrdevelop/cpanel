package Cpanel::Crypt::GPG::Generate;

# cpanel - Cpanel/Crypt/GPG/Generate.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Crypt::GPG::Generate

=head1 SYNOPSIS

    use Cpanel::Crypt::GPG::Generate ();
    my $gpg = Cpanel::Crypt::GPG::Generate->new();
    my $result = $gpg->generate_key( { name => 'bender', email => 'bender@benderisgreat.tld' } );

=head1 DESCRIPTION

Provide functionality to generate GPG keys.

This module relies on a feature GPG provides of generating keys in batch mode.
That functionality is documented here:
L<https://gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html#Unattended-GPG-key-generation>.

=cut

use parent qw( Cpanel::Crypt::GPG::Base );

use Cpanel::Exception       ();
use Cpanel::SafeRun::Object ();
use Time::Piece             ();

use constant SUPPORTED_KEY_SIZES     => ( 1024, 2048, 3072, 4096 );
use constant MINIMUM_KEY_NAME_LENGTH => 5;
use constant MAX_EXPIRE_YEAR         => 2105;
use constant DEFAULT_EXPIRE_TIME     => '1y';
use constant DEFAULT_KEY_SIZE        => 2048;

=head1 INSTANCE METHODS

=head2 generate_key( \%opts_hr )

=head3 Purpose

Generates a GPG key with the specified options.

=head3 Arguments

=over 3

=item C<< \%opts_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< name => $gpg_user_name >> [in, required]

The name of the user to associate with the key.

=item C<< email => $gpg_email >> [in, required]

The email address of the user to associate with the key.

=item C<< expire => 1560363242 >> [in, optional]

Unix timestamp - Set the expiration date of the key.

Defaults to 1 year from current date.

Cannot be used with C<no_expire>.

=item C<< no_expire => 1 >> [in, optional]

Boolean - Creates a key without an expiration date.

Cannot be used with C<expire>.

=item C<< passphrase => 'long_passphrases_are_good' >> [in, optional]

Sets the passphrase for the key.

=item C<< comment => 'a helpful comment is helpful' >> [in, optional]

Sets the comment for the key. This will be displayed when listing keys so it
can be helpful to remember what the key is used for.

=item C<< keysize => 2048 >> [in, optional]

Sets the keysize of the the key.

Defaults to C<2048>.

=back

=back

=head3 Returns

A string containing the output of the key generation, usually it's just an empty string.

=head3 Throws

=over 3

=item When parameters are invalid

=item When GPG cannot be found on the system

=item When GPG key generation fails

=back

=cut

sub generate_key {
    my ( $self, $opts_hr ) = @_;
    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $gpg_bin    = $self->get_gpg_bin();
    my $valid_opts = _validate_opts_or_die($opts_hr);

    my ( $comment, $passphrase, $expire_date ) = ( '', '', '' );
    $comment    = "Name-Comment: $valid_opts->{comment}" if length $valid_opts->{comment};
    $passphrase = 'Passphrase: ';
    $passphrase .= length $valid_opts->{passphrase} ? $valid_opts->{passphrase} : "''";

    if ( length $valid_opts->{expire} && !$valid_opts->{no_expire} ) {
        my $expire = _convert_expire_to_gpg_format( $valid_opts->{expire} );
        $expire_date = "Expire-Date: $expire";
    }

    # Create a structure used to generate keys as described in the docs
    # https://gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html#Unattended-GPG-key-generation
    my $key = <<"EOM";
\%echo Generating a standard key
Key-Type: RSA
Key-Length: $valid_opts->{keysize}
Subkey-Type: RSA
Subkey-Length: $valid_opts->{keysize}
Name-Real: $valid_opts->{name}
$comment
Name-Email: $valid_opts->{email}
$expire_date
#1w 1day etc
$passphrase
# Do a commit here, so that we can later print "done" :-)
\%commit
\%echo done
EOM

    # The gen-key call should generate the ~/.gnupg directory and files in the gpg homedir,
    # as well as generating the key.
    my $gen_key_run = Cpanel::SafeRun::Object->new_or_die(
        program => $gpg_bin,
        args    => [
            '--no-secmem-warning',
            '-v',
            '--batch',
            '--gen-key',
            '-a',
            $self->{homedir} ? ( '--homedir' => $self->{homedir} ) : ()
        ],
        stdin => $key,    # you can pass the key data to stdin instead of writing it to a temp file
    );

    return $gen_key_run->stdout();
}

sub _convert_expire_to_gpg_format {
    my ($expire) = @_;

    # handle the default case
    return $expire if $expire eq DEFAULT_EXPIRE_TIME();

    my $time;
    eval { $time = Time::Piece->strptime( $expire, "%s" ) } or do {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,UNIX] epoch timestamp.', [$expire] );
    };

    # GPG uses the compact ISO format for times (e.g. "20000815T145012")
    # See https://gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html#Unattended-GPG-key-generation
    $time->time_separator("");
    $time->date_separator("");
    return $time->datetime();
}

sub _validate_opts_or_die {
    my ($opts_hr) = @_;

    my $validation_tests = {
        'name'       => { 'required' => 1, 'test'    => \&_validate_name, },
        'email'      => { 'required' => 1, 'test'    => \&_validate_email, },
        'expire'     => { 'required' => 0, 'default' => DEFAULT_EXPIRE_TIME(), 'test' => \&_validate_expire },
        'passphrase' => { 'required' => 0, 'default' => '',                    'test' => \&_validate_passphrase },
        'keysize'    => { 'required' => 0, 'default' => DEFAULT_KEY_SIZE(),    'test' => \&_validate_keysize },
        'no_expire'  => { 'required' => 0, 'default' => 0,                     'test' => \&_validate_no_expire },
        'comment'    => { 'required' => 0, 'default' => '', },
    };

    my $valid_config_hr;
    foreach my $key ( keys %{$validation_tests} ) {
        if ( $validation_tests->{$key}->{'required'} && !defined $opts_hr->{$key} ) {
            die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$key] );
        }

        if (   defined $opts_hr->{$key}
            && defined $validation_tests->{$key}->{'test'}
            && !eval { $validation_tests->{$key}->{'test'}->( $opts_hr->{$key} ); } ) {
            die Cpanel::Exception::create(
                'InvalidParameter',
                'Invalid configuration for the parameter “[_1]”: [_2]',
                [ $key, Cpanel::Exception::get_string_no_id($@) ]
            );
        }
        else {
            $valid_config_hr->{$key} = $opts_hr->{$key} // $validation_tests->{$key}->{'default'};
        }
    }

    return $valid_config_hr;
}

sub _validate_name {
    my ($name) = @_;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be at least [quant,_2,character,characters] long.', [ 'name', MINIMUM_KEY_NAME_LENGTH() ] )
      if length $name < MINIMUM_KEY_NAME_LENGTH();
    return 1;
}

sub _validate_email {
    my ($email) = @_;
    require Cpanel::Validate::EmailRFC;
    die Cpanel::Exception::create( 'InvalidParameter', 'That is not a valid email address.' )
      if !Cpanel::Validate::EmailRFC::is_valid($email);
    return 1;
}

sub _validate_keysize {
    my ($keysize) = @_;
    die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be [list_or_quoted,_2].', [ 'keysize', [SUPPORTED_KEY_SIZES] ] )
      if !grep { $_ == $keysize } (SUPPORTED_KEY_SIZES);
    return 1;
}

sub _validate_expire {
    my ($expire) = @_;

    require Cpanel::Validate::Time;
    Cpanel::Validate::Time::epoch_or_die($expire);

    my $time;
    eval { $time = Time::Piece->strptime( $expire, "%s" ) } or do {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,UNIX] epoch timestamp.', [$expire] );
    };

    # The GPG documentation says that it does not validate dates in the past
    die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” value must be a future date.", [$expire] )
      if $time->epoch() < time();

    # The GPG documentation says that it does not support years greater than 2105
    die Cpanel::Exception::create( 'InvalidParameter', 'The expire date is too far in the future.' )
      if $time->year() > MAX_EXPIRE_YEAR();

    return 1;
}

sub _validate_no_expire {
    my ($no_expire) = @_;
    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die($no_expire);
    return 1;
}

sub _validate_passphrase {
    my ($passphrase) = @_;
    die Cpanel::Exception::create( 'InvalidParameter', 'The passphrase may not begin or end with a space.' )
      if $passphrase =~ m<\A\s|\s\z>;
    return 1;
}

1;
