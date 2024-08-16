package Cpanel::Security::Authn::APITokens;

# cpanel - Cpanel/Security/Authn/APITokens.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens - Manage a user's API tokens

=head1 DESCRIPTION

This base class encapsulates the logic to read a user’s API tokens.
Look at service-specific subclasses for implementation specifics.

=head1 SUBCLASS INTERFACE

Subclasses must define the following:

=over

=item * C<_SERVICE_NAME()> - The name of the service (e.g., C<whostmgr>).

=back

=cut

#----------------------------------------------------------------------

use List::Util                            ();
use Cpanel::Exception                     ();
use Cpanel::LoadModule                    ();
use Cpanel::Transaction::File::JSONReader ();

use constant _ENOENT => 2;

# Accessed from Write.pm and tests.
our $_TOKENS_DIR;

BEGIN {
    $_TOKENS_DIR = '/var/cpanel/authn/api_tokens_v2';
}

=head1 CLASS METHODS

=head2 new($args_hr)

Object Constructor.

=over 3

=item C<< \%args_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< user => $username >> [in, required]

The name of the user whose API tokens will be manipulated via the object.

=back

=back

B<Returns>: On failure, throws an exception.  On success, returns an object.

=cut

sub new {
    my ( $class, $opts ) = @_;

    my $self = bless {}, $class;
    $self->_initialize($opts);

    return $self;
}

#----------------------------------------------------------------------

=head1 OBJECT METHODS

=head2 verify_token($plaintext_token)

Verifies whether the plaintext token is valid for the user.

=over 3

=item C<< $plaintext_token >> [in, required]

A string containing the plaintext token to verify.

=back

B<Returns>: An instance of the service’s subclass of
L<Cpanel::Security::Authn::APITokens::Object>, or undef if
no such token exists.

=cut

sub verify_token {
    my ( $self, $plaintext_token ) = @_;

    my $obj = $self->look_up_by_token($plaintext_token);

    if ($obj) {
        my $ip_addresses = $obj->get_whitelist_ips();
        $obj = undef if !$self->_remote_ip_allowed( $ENV{REMOTE_ADDR} || '', $ip_addresses );
    }

    return $obj;
}

=head2 $ret = I<OBJ>->look_up_by_token( $PLAINTEXT_TOKEN )

Like C<verify_token()> but omits the IP address check. Can thus be used to
look up a token’s entry by the token itself.

This does, though, retain the expiry check; an expired token is thus
effectively nonexistent.

=cut

sub look_up_by_token ( $self, $plaintext_token ) {
    require Digest::SHA;
    my $token_hash = Digest::SHA::sha512_hex($plaintext_token);

    my $data = $self->_read_data();

    my $token_hr = $data->{'tokens'}->{$token_hash};

    return undef if !$token_hr;

    my $obj = $self->_token_object_class()->new(%$token_hr);

    my $expires_at = $obj->get_expires_at();
    return undef if $expires_at && $expires_at < time();

    return $obj;
}

#----------------------------------------------------------------------

=head2 get_token_details_by_name($token_name)

Looks up a token by name.

=over 3

=item C<< $token_name >> [in, required]

The token name to look up.

=back

B<Returns>: An instance of the service’s subclass of
L<Cpanel::Security::Authn::APITokens::Object>, or undef if
no token by the given name exists.

=cut

sub get_token_details_by_name {
    my ( $self, $token_name ) = @_;

    my $tokens_hr = $self->_read_data()->{'tokens'};

    my $token_obj;

    if ( $token_obj = List::Util::first { $_->{'name'} eq $token_name } values %{$tokens_hr} ) {
        my $obj_class = $self->_token_object_class();

        $token_obj = $obj_class->new(%$token_obj);
    }

    return $token_obj;
}

#----------------------------------------------------------------------

=head2 read_tokens()

Read the tokens configured for the user.

B<Returns>: A HashRef of the form:

    {
        'hash_of_token1' => $obj1,
        'hash_of_token2' => $obj2,
    }

… where the objects are instances of the service’s
L<Cpanel::Security::Authn::APITokens::Object> subclass.

=cut

sub read_tokens {
    my $self = shift;
    my $data = $self->_read_data();

    my %copy = %{ $data->{'tokens'} || {} };

    my $obj_class = $self->_token_object_class();

    $_ = $obj_class->new(%$_) for values %copy;

    return \%copy;
}

my %loaded_object_class;

sub _token_object_class {
    my ($class) = @_;

    return $loaded_object_class{ $class->_SERVICE_NAME() } ||= do {
        my $namespace = 'Cpanel::Security::Authn::APITokens::Object::' . $class->_SERVICE_NAME();
        Cpanel::LoadModule::load_perl_module($namespace);
    };
}

#----------------------------------------------------------------------

=head2 $users_ar = I<CLASS>->list_users()

Returns an array reference of names of users that have tokens for the
CLASS’s associated service.

This throws an exception on failure to determine the information.

=cut

sub list_users {
    my ($class) = @_;

    my $dir = $class->_base_dir();

    my @users;

    if ( opendir my $dh, $dir ) {
        while ( my $file = readdir $dh ) {
            if ( $file =~ m/([^\.]+)\.json$/ ) {
                push @users, $1;
            }
        }
    }
    elsif ( $! != _ENOENT() ) {
        die "opendir($dir): $!";
    }

    return \@users;
}

#----------------------------------------------------------------------

=head2 $mtime = I<CLASS>->get_user_mtime( $USERNAME )

Returns the time when the user with the given $USERNAME’s token
data was last modified. If there is no such data, then undef is returned.

An exception is thrown on failure.

=cut

sub get_user_mtime {
    my ( $class, $username ) = @_;

    local $!;

    require Cpanel::Autodie;
    return Cpanel::Autodie::exists( $class->_get_filename($username) ) ? ( stat _ )[9] : undef;
}

#----------------------------------------------------------------------

sub _create_transaction {
    my ( $self, $username ) = @_;

    my $filename = $self->_get_filename($username);

    return Cpanel::Transaction::File::JSONReader->new(
        path => $filename,
    );
}

sub _get_filename {
    my ( $class, $username ) = @_;

    my $dir = $class->_base_dir();
    return "$dir/$username.json";
}

sub _read_data {
    my $self = shift;
    return $self->{'_data'} if $self->{'_data'} && 'HASH' eq ref $self->{'_data'};

    my $data = $self->{'_transaction_obj'}->get_data();
    $self->{'_data'} = ( ref $data eq 'SCALAR' ? ${$data} : $data ) || {};
    return $self->{'_data'};
}

sub _initialize {
    my ( $self, $opts ) = @_;

    my $username = delete $opts->{'user'} // die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] );

    # Accessed in subclasses.
    $self->{'_username'} = $username;

    $self->{'_transaction_obj'} = $self->_create_transaction($username);

    return 1;
}

sub _base_dir {
    my ($self) = @_;

    return "$_TOKENS_DIR/" . $self->_SERVICE_NAME();
}

sub _remote_ip_allowed {
    my ( $self, $remote_addr, $whitelist_ips ) = @_;
    return 0 if !$remote_addr;
    return 1 if !$whitelist_ips;    # No whitelist, so any ips allowed.

    require Net::IP;

    my $remote_ip = eval { Net::IP->new($remote_addr) };
    return 0 if !$remote_ip;

    foreach my $ip_or_range (@$whitelist_ips) {
        my $range   = Net::IP->new($ip_or_range);
        my $overlap = $range->overlaps($remote_ip);
        next unless defined $overlap;
        return 1 if $overlap == $Net::IP::IP_B_IN_A_OVERLAP || $overlap == $Net::IP::IP_IDENTICAL;
    }

    return 0;
}

1;
