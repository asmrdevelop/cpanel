package Cpanel::Security::Authn::APITokens::Write;

# cpanel - Cpanel/Security/Authn/APITokens/Write.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Write

=head1 SYNOPSIS

See end classes

=head1 DESCRIPTION

This subclass of L<Cpanel::Security::Authn::APITokens> implements
write logic for the API Tokens datastore.

Note that this class is itself a base class; see the SUBCLASS INTERFACE
defined below.

=head1 SUBCLASS INTERFACE

A subclass of this class must define, in addition to the methods that
L<Cpanel::Security::Authn::APITokens> requires, the following methods:

=over

=item * C<_BASE_DIR_PERMISSIONS()> - The permissions to assign for the
service’s tokens directory.

=item * C<_TOKEN_FILE_PERMISSIONS()> - The permissions to assign for the
user’s tokens file itself.

=item * C<_OWNERSHIP($USERNAME)> - The ownership IDs for the entry
for the given $USERNAME. Must return a list of: ( $UID, $GID ).

=item * C<_service_token_parts( \%OPTS )> - Returns a list of key/value
pairs to store from arguments to create/update/import operations.

=item * C<_normalize_token_data( \%OPTS )> - Normalizes the token’s
data as it will be saved to disk.

=item * C<_validate_for_create( \%OPTS )> - Validate options for
token creation.

=item * C<_validate_for_update( \%TOKEN_HR, \%OPTS )> - Validate options for
token update.

=back

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Security::Authn::APITokens );

use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::Transaction::File::JSON ();

our $TOKEN_LENGTH = 32;

our $_TOKENS_DIR;
*_TOKENS_DIR = \$Cpanel::Security::Authn::APITokens::_TOKENS_DIR;

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 $renamed_yn = I<CLASS>->rename_user( $OLDNAME => $NEWNAME )

Renames a user in the datastore, if such exists.

Returns 1 if a rename occurred or 0 if no user with the given $OLDNAME
exists.

An exception is thrown on failure.

=cut

sub rename_user {
    my ( $class, $oldname, $newname ) = @_;

    my $dir = $class->_base_dir();

    require Cpanel::Autodie;
    return Cpanel::Autodie::rename_if_exists(
        $class->_get_filename($oldname),
        $class->_get_filename($newname),
    );
}

#----------------------------------------------------------------------

=head2 $removed_yn = I<CLASS>->remove_user( $USERNAME )

Removes a user from the datastore, if such exists.

Returns 1 if a removal occurred or 0 if no user with the given $NAME
exists.

An exception is thrown on failure.

=cut

sub remove_user {
    my ( $class, $username ) = @_;

    require Cpanel::Autodie;
    return Cpanel::Autodie::unlink_if_exists( $class->_get_filename($username) );
}

#----------------------------------------------------------------------

=head1 OBJECT METHODS

=head2 create_token($opts_hr)

Create a new token with the name specified in C<$opts_hr>.

Upon creating the token successfully, the caller must use the C<save_changes_to_disk()> method
in order to save the new token to the disk.

=over 3

=item C<< \%opts_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< name => $token_name >> [in, required]

The name to associate with the generated token.

This name must be B<unique> - if a token by the same name exists, then an
exception is thrown.

=item … and the appropriate service-specific arguments.

=back

B<Returns>: On failure, throws an exception. On success, the following data is returned in a hashref:

=over 3

=item C<token>

The plaintext API token that was generated.

=item C<name>

The name of the API token as specified by the caller.

=item C<create_time>

The time the API token was created (unixepoch)

=item … and the appropriate service-specific returns.

=back

=back

=cut

sub create_token {
    my ( $self, $opts_hr ) = @_;

    require Cpanel::Rand::Get;
    my $plaintext_token = Cpanel::Rand::Get::getranddata( $TOKEN_LENGTH, [ 0 .. 9, 'A' .. 'Z' ] );
    my $token_details   = $self->_import_token( { %$opts_hr, token => $plaintext_token } );

    return {
        %{$token_details},
        'token' => $plaintext_token,
    };
}

# Add a new token with the name specified in C<$opts_hr>.
# Upon creating the token successfully, the caller must use the
# C<save_changes_to_disk()> method in order to save the new token to the disk.
#
# Inputs are the same as for C<create_token()>, but a C<token> is also
# required, and C<create_time()> may also be given.
#
# Outputs are the same as for C<create_token()>, but no C<token> is returned.
#
sub _import_token {
    my ( $self, $opts_hr ) = @_;

    die 'Need hashref!' if 'HASH' ne ref $opts_hr;

    my %opts_copy = %$opts_hr;

    my $token = delete $opts_copy{'token'};
    _validate_token($token);

    $self->_validate_for_create( \%opts_copy );

    require Digest::SHA;
    my $token_hash = Digest::SHA::sha512_hex($token);

    local $opts_hr->{'token_hash'} = $token_hash;

    return $self->_import_token_hash_post_validate($opts_hr);
}

sub _validate_token {
    my ($token) = @_;

    if ( $token !~ m<\A[0-9A-Z]{$TOKEN_LENGTH}\z> ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,API] token. [asis,API] tokens are [quant,_2,character,characters] long and contain only the following [numerate,_3,character,characters]: [join,~, ,_4]', [ $token, $TOKEN_LENGTH, 36, [ 'A-Z', '0-9' ] ] );
    }

    return;
}

#----------------------------------------------------------------------

sub _import_token_hash_post_validate {
    my ( $self, $opts_hr ) = @_;

    my $token_name = $opts_hr->{'name'};
    my $token_hash = $opts_hr->{'token_hash'};

    my $data = $self->_read_data();

    # If the new entry matches an existing hash, then overwrite that
    # existing entry, regardless of whether the token name matches.
    # Otherwise, require a different name.
    #
    if ( !$data->{'tokens'}->{$token_hash} ) {
        die Cpanel::Exception::create( 'EntryAlreadyExists', 'A conflicting [asis,API] token with the name “[_1]” already exists.', [$token_name] )
          if grep { $_->{'name'} eq $token_name } values %{ $data->{'tokens'} };
    }

    my $time = $opts_hr->{'create_time'};

    my $token_details = {
        'name'        => $token_name,
        'create_time' => $time // scalar time,

        %{$opts_hr}{ $self->_NON_NAME_TOKEN_PARTS() },
    };

    $self->_normalize_token_data($token_details);

    $data->{'tokens'}->{$token_hash} = $token_details;
    $self->_set_data($data);

    return $token_details;
}

=head2 $details_hr = I<OBJ>->import_token_hash( \%OPTS )

Imports an existing token, potentially B<OVERWRITING> a conflicting token.
(See below.)

Afterwards, the caller B<must> use the C<save_changes_to_disk()> method
to save the new token to the disk, or else the changes will be lost.

Inputs are the same as for C<create_token()>, but a C<token_hash> is required,
and C<create_time()> may also be given.

Outputs are the same as for C<create_token()>, but no C<token> is returned.

=head3 Conflict resolution

=over

=item * If an existing token uses the same C<token_hash> as the new one,
we overwrite the old one.

=item * If an existing token uses a I<different> C<token_hash> but has
the same name, an exception is thrown.

=back

=cut

sub import_token_hash {
    my ( $self, $opts_hr ) = @_;

    die 'Need hashref!' if 'HASH' ne ref $opts_hr;

    my %opts_copy = %$opts_hr;

    my $token_hash = delete $opts_copy{'token_hash'};
    _validate_token_hash($token_hash);

    my $create_time = delete $opts_copy{'create_time'};
    if ( defined $create_time ) {
        _validate_create_time($create_time);
    }

    $self->_validate_for_create( \%opts_copy );

    return $self->_import_token_hash_post_validate($opts_hr);
}

# This isn’t in APITokens/Validate.pm because it’s only needed here.
sub _validate_create_time {
    my ($time) = @_;

    return if length($time) && ( $time !~ tr<0-9><>c ) && $time <= time();

    die "“$time” is not a valid “create_time”.";
}

sub _validate_token_hash {
    if ( $_[0] !~ m<\A[a-f0-9]{128}\z> ) {
        die "“token_hash” ($_[0]) is invalid.";
    }

    return;
}

#----------------------------------------------------------------------

=head2 revoke_token($token_name)

Revokes the token specified for the user.

Upon revoking the token successfully, the caller must use the C<save_changes_to_disk()> method
in order to save the new token to the disk.

=over 3

=item C<< $token_name >> [in, required]

A string containing the name of the token to revoke.

=back

B<Returns>: A boolean value indicating whether the token is was successfully revoked (C<1>) or not (C<0>).

=cut

sub revoke_token {
    my ( $self, $token_name ) = @_;

    my $data = $self->_read_data();
    foreach my $token ( keys %{ $data->{'tokens'} } ) {
        if ( $data->{'tokens'}->{$token}->{'name'} eq $token_name ) {
            delete $data->{'tokens'}->{$token};
            $self->_set_data($data);
            return 1;
        }
    }

    return 0;
}

#----------------------------------------------------------------------

=head2 update_token($opts_hr)

Update the token with the name specified in C<$opts_hr>.

Upon updating the token successfully, the caller must use the C<save_changes_to_disk()> method
in order to save the changes to the disk.

=over 3

=item C<< \%opts_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< name => $token_name >> [in, required]

The name to token to update.

=item C<< new_name => $token_name >> [in, optional]

The new name to assign to the token.

This name must be B<unique> - if a token by the same name exists, then an
exception is thrown.

=item … and the appropriate service-specific arguments.

=back

B<Returns>: On failure, throws an exception. On success, the following data is returned in a hashref:

=over 3

=item C<name>

The name of the API token as specified by the caller.

=item C<create_time>

The time the API token was created (unixepoch)

=item … and the appropriate service-specific arguments.

=back

=back

=cut

sub update_token {
    my ( $self, $opts_hr ) = @_;

    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $data = $self->_read_data();

    for my $token_hr ( values %{ $data->{'tokens'} } ) {
        next if $token_hr->{'name'} ne $opts_hr->{'name'};

        $self->_validate_for_update( $token_hr => $opts_hr );

        my $new_name = $opts_hr->{'new_name'};

        if ( defined($new_name) && ( $opts_hr->{'name'} ne $new_name ) ) {
            my $is_used = $self->get_token_details_by_name($new_name);
            if ($is_used) {
                die Cpanel::Exception::create( 'EntryAlreadyExists', 'An [asis,API] token with the name “[_1]” already exists.', [$new_name] );
            }

            $token_hr->{'name'} = $new_name;
        }

        for my $svc_part ( $self->_NON_NAME_TOKEN_PARTS() ) {
            if ( exists $opts_hr->{$svc_part} ) {
                $token_hr->{$svc_part} = $opts_hr->{$svc_part};
            }
        }

        $self->_normalize_token_data($token_hr);

        $self->_set_data($data);

        return $token_hr;
    }

    die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,API] token “[_1]” does not exist.', [ $opts_hr->{'name'} ] );
}

#----------------------------------------------------------------------

=head2 save_changes_to_disk()

Saves any changes to the disk.

B<Returns>: On failure, throws an exception. On success, returns C<1>.

=cut

sub save_changes_to_disk {
    my $self = shift;

    my $ret = $self->{'_transaction_obj'}->save_or_die();

    delete $self->{'_needs_save'};

    return $ret;
}

#----------------------------------------------------------------------

sub DESTROY {
    my ($self) = @_;

    if ( $self->{'_needs_save'} ) {
        die "$self DESTROY without needed save_changes_to_disk()!";
    }

    return;
}

sub _set_data {
    my ( $self, $data_hr ) = @_;

    $self->{'_transaction_obj'}->set_data($data_hr);
    $self->{'_needs_save'} = 1;

    return;
}

sub _create_transaction {
    my ( $self, $username ) = @_;

    my $service_dir = $self->_base_dir();

    if ( !-d $service_dir ) {
        $self->_create_base_dirs();
    }

    my $filename = $self->_get_filename($username);

    return Cpanel::Transaction::File::JSON->new(
        path        => $filename,
        permissions => $self->_TOKEN_FILE_PERMISSIONS(),
        ownership   => [ $self->_TOKEN_FILE_OWNERSHIP($username) ],
    );
}

sub _base_dirspec {
    my ($self) = @_;

    return [

        # In reality we will most likely never get to a stage where
        # /var/cpanel doesn't exist when we hit this code path, but we
        # still ensure that this codepath doesn't fail in such situations.
        #
        # TODO: Eliminate duplication of the mode for these directories.
        [ '/var/cpanel',       { mode => 0755 } ],
        [ '/var/cpanel/authn', { mode => 0711 } ],

        # Since some services allow unprivileged access to API tokens
        # this has to be world-executable.
        [ $_TOKENS_DIR, { mode => 0711 } ],

        # Each service’s module will define this.
        [ $self->_base_dir(), { mode => $self->_BASE_DIR_PERMISSIONS() } ],
    ];
}

sub _create_base_dirs {
    my ($class) = @_;

    die 'Bad $_TOKENS_DIR!' if !$_TOKENS_DIR;

    require File::Path;
    foreach my $dirspec ( @{ $class->_base_dirspec() } ) {
        $dirspec->[1]->{'error'} = \my $errors;
        File::Path::make_path( @{$dirspec} );
        next if !( $errors && scalar @{$errors} );

        # The errors returned by File::Path are an array of hash references.
        # Each hash contains a single key/value pair.
        my ( $path, $error ) = %{ $errors->[0] };
        die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ 'path' => $path, 'error' => $error ] );
    }
    return;
}

sub _NON_NAME_TOKEN_PARTS {
    my ($self) = @_;

    my $module = 'Cpanel::Security::Authn::APITokens::Validate::' . $self->_SERVICE_NAME();

    return Cpanel::LoadModule::load_perl_module($module)->NON_NAME_TOKEN_PARTS();
}

sub _normalize_ip_list {
    my ( $self, @ips ) = @_;
    require Cpanel::ArrayFunc::Uniq;
    require Net::IP;

    return Cpanel::ArrayFunc::Uniq::uniq(
        map {
            # It's customary to discard the CIDR suffix for a single host address (/32 for v4 or /128 for v6).
            # With Net::IP an easy way to know a host address for any IP version is if no 0's exist in the binmask.
            my $suffix = index( $_->binmask, '0' ) == -1 ? q{} : q{/} . $_->prefixlen();
            $_->ip() . $suffix;
          }
          sort {
            # Sort by IP version first (4 -> 6) and then by integer address.
                 $a->version() <=> $b->version()
              || $a->intip()   <=> $b->intip()
          }
          map {
            # The token parts validation step should be throwing an exception
            # for any IPs that wouldn't result in Net::IP returning an object
            # before we get to this point, but in case a bad IP somehow gets
            # through such as by manually editing a config file, we want it to
            # be known.
            Net::IP->new($_) // die Cpanel::Exception->create( "Invalid IP address or range: “[_1]”", [$_] );
          } @ips
    );
}

1;
