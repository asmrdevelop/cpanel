package Cpanel::UserManager::Record;

# cpanel - Cpanel/UserManager/Record.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Carp                        ();
use Cpanel::Auth::Digest::Realm ();
use Cpanel::Auth::Generate      ();
use Cpanel::Hostname            ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::LoadModule                ();
use Cpanel::UserManager::Issue        ();
use Cpanel::Validate::EmailRFC        ();
use Cpanel::Validate::Username        ();
use Cpanel::Validate::VirtualUsername ();
use Cpanel::ValidationAccessor 'antlers';
use Cpanel::Validate::Domain ();

=head1 NAME

Cpanel::UserManager::Record

=cut

# Default all services to "off" unless we learn otherwise
my %SERVICE_DEFAULTS = (
    email => {
        enabled => 0,
    },
    ftp => {
        enabled => 0,
    },
    webdisk => {
        enabled => 0,
    },
);

sub VALIDATION { return 1 }

# Basic attributes
has type => ( is => 'rw', isa => 'Str' );
sub validate_type { shift; return shift() =~ /^(?:sub|hypothetical|service|cpanel)$/ }

has special => ( is => 'rw', type => 'Num' );    # automatically generated; see accessor
sub validate_special { goto &_validate_boolean }

has can_delete => ( is => 'ro', type => 'Num' );
sub validate_can_delete { Carp::croak lh()->maketext('The [asis,can_delete] attribute is [asis,read-only].') }

has can_set_quota => ( is => 'rw', type => 'Num' );
sub validate_can_set_quota { goto &_validate_boolean }

has can_set_password => ( is => 'rw', type => 'Num' );
sub validate_can_set_password { goto &_validate_boolean }

has username => ( is => 'rw', isa => 'Str' );

has team_owner => ( is => 'rw', isa => 'Str' );

sub validate_username {
    my ( $self, $username ) = @_;
    Carp::croak lh()->maketext('You must enter a username.') if !length($username);
    return $self->_validate_full_username( $username, undef );
}

sub _validate_full_username {
    my ( $self, $username, $domain ) = @_;

    my $full_username_would_be = join( '@', $username || $self->username // (), $domain || $self->domain // () );
    if ( 'sub' eq $self->type ) {

        # Even though this is the validator for username, we want to validate the generated full username value,
        # which is based on a combination of the username and the domain. This allows us to do the total length
        # check of the two put together.
        Cpanel::Validate::VirtualUsername::validate_or_die($full_username_would_be);
    }
    elsif ( 'cpanel' eq $self->type ) {
        Cpanel::Validate::Username::validate_or_die($full_username_would_be);
    }
    return 1;
}

has domain => ( is => 'rw', isa => 'Str' );

sub validate_domain {
    my ( $self, $domain ) = @_;
    if (
          !$domain
        && $self->type ne 'cpanel'     # cPanel username does not include a domain
        && $self->type ne 'service'    # some service accounts don't have a domain
    ) {
        Carp::croak lh()->maketext('You must enter a domain.');
    }
    elsif ( $self->type ne 'cpanel' ) {

        # If the type is not cpanel its a virtual user
        # and we must validate the domain
        Cpanel::Validate::Domain::valid_domainname_for_customer_or_die($domain);
    }
    return 1;
}
has full_username => ( is => 'ro', isa => 'Str' );    # the full_username attribute is automatically generated; see full_username accessor
has real_name     => ( is => 'rw', isa => 'Str' );

sub validate_real_name {
    my ( $self, $value ) = @_;

    # Allow most characters, since we don't know which characters might be needed to represent a
    # person's name. Forbid HTML-related characters just in case the frontend doesn't HTML encode.
    die lh()->maketext('The real name field cannot contain [asis,HTML] characters.') . "\n" if $value && $value =~ tr/<>&//;
    return 1;
}

has alternate_email => ( is => 'rw', isa => 'Str' );

sub validate_alternate_email {
    my ( undef, $value ) = @_;    # discard $self
    return 1 if !$value;          # Allow it to be valid when empty since alternate_email is an optional field
    return Cpanel::Validate::EmailRFC::is_valid($value);
}

has phone_number => ( is => 'rw', isa => 'Str' );

sub validate_phone_number {
    my ( $self, $value ) = @_;

    # The intent of this regular expression is to match any valid E.164 phone number.
    #
    # Some notes about this format:
    #
    #   - There are no parentheses or hyphens. For example, the American phone number (222) 555-8888 is encoded as +12225558888.
    #   - +1 is the country code for the United States. Non-US phone numbers will have a different prefix.
    #   - The leading plus sign may or may not be present.
    #   - Extensions are represented with a suffix of ;ext=XXXX, where XXXX is the extension.
    #   - There are additional limitations of this format (for example, which country codes are valid, and the maximum number
    #     length), which are not enforced by this regular expression. The goal is only to ensure that the data entered appears
    #     to be on the right track, not to comprehensively enforce the rules of the E.164 format.

    return !$value || $value =~ /^ [+]? [0-9 #*]+ (?: ;ext=[0-9]+ )? $/x;
}

has avatar_url => ( is => 'rw', isa => 'Str' );

sub validate_avatar_url {
    my ( $self, $value ) = @_;

    # Can't forbid HTML characters, since some URLs have ampersands. Just need to rely on the frontend to HTML encode this.
    return !$value || $value =~ m{^https://};
}

has services        => ( is => 'rw' );    # hash ref
has issues          => ( is => 'rw' );    # array ref
has annotation_list => ( is => 'rw' );    # Cpanel::UserManager::AnnotationList object

#################################################################
## Merge-related attributes
#################################################################
has merge_candidates           => ( is => 'rw' );    # array ref
has dismissed_merge_candidates => ( is => 'rw' );    # array ref

has synced_password => ( is => 'rw', isa => 'Num' );       # boolean
sub validate_synced_password { goto &_validate_boolean }
has sub_account_exists => ( is => 'rw', isa => 'Num' );    # boolean
has has_siblings       => ( is => 'rw', isa => 'Num' );    # boolean
has parent_type        => ( is => 'rw', isa => 'Str' );
has dismissed          => ( is => 'rw', isa => 'Num' );    # boolean

#################################################################
## Invite-related attributes
#################################################################

has has_invite => ( is => 'rw', isa => 'Num' );            # boolean
sub validate_has_invite { goto &_validate_boolean }

has invite_expiration => ( is => 'rw', isa => 'Num' );

sub validate_invite_expiration {
    my ( $self, $timestamp ) = @_;
    return ( defined $timestamp ? $timestamp > 1_300_000_000 : 1 );    # Just a basic sanity check. This is 2011-03-13
}

has has_expired_invite => ( is => 'ro', isa => 'Num' );                # boolean

sub has_expired_invite {
    my $self = shift;
    return 0 if !$self->has_invite;
    return 1 if !$self->invite_expiration;
    return ( time() > $self->invite_expiration );
}

#################################################################
## Database-specific attributes
#################################################################
has guid             => ( is => 'rw', isa => 'Str' );
has password         => ( is => 'rw', isa => 'Str' );
has password_hash    => ( is => 'rw', isa => 'Str' );
has digest_auth_hash => ( is => 'rw', isa => 'Str' );

# The distinction drawn here between "intrinsic" and "dynamic" attributes:
#   - Intrinsic: Part of the object itself; directly stored as an attribute. Can be read internally via the hash element.
#   - Dynamic: Generated based on other attributes; not stored. Must always be read, even internally, via the accessor.
#
# The distinction drawn here between "boolean" and "other" attributes:
#   - Boolean: A boolean value; if undefined, will default to 0 for consistency.
#   - Other: Anything other than a boolean value; if undefined, will remain undef.

sub INTRINSIC_BOOLEAN_ATTRIBUTES {
    return qw(
      has_invite
      synced_password
    );
}

sub DYNAMIC_BOOLEAN_ATTRIBUTES {
    return qw(
      can_delete
      can_set_password
      can_set_quota
      dismissed
      has_expired_invite
      has_siblings
      special
      sub_account_exists
    );
}

sub INTRINSIC_OTHER_ATTRIBUTES {
    return qw(
      alternate_email
      avatar_url
      digest_auth_hash
      domain
      guid
      invite_expiration
      password_hash
      phone_number
      real_name
      type
      username
    );
}

sub DYNAMIC_OTHER_ATTRIBUTES {
    return qw(
      dismissed_merge_candidates
      full_username
      issues
      merge_candidates
      parent_type
      services
      team_owner
    );
}

sub as_hashref {
    my ( $self, %args ) = @_;

    # Initialize guid for object if not already done. This step is needed because the guid
    # is one of the intrinsic attributes and therefore subject to access via hash keys.
    $self->guid if !$self->{guid};

    my @boolean_attributes = map { $_ => $self->{$_} || 0 } $self->INTRINSIC_BOOLEAN_ATTRIBUTES();
    push @boolean_attributes, map { $_ => $self->$_ || 0 } $self->DYNAMIC_BOOLEAN_ATTRIBUTES();

    my @other_attributes = map { $_ => $self->{$_} } $self->INTRINSIC_OTHER_ATTRIBUTES();

    push @other_attributes, map {
        my $attribute           = $_;
        my $serializable_getter = $attribute . '_serializable';
        my $getter              = $self->can($serializable_getter) || $attribute;
        $attribute => $self->$getter;
    } $self->DYNAMIC_OTHER_ATTRIBUTES();

    my $as_hashref = {
        @boolean_attributes,
        @other_attributes,
    };

    # These attributes don't need to be presented to most callers who request the as_hashref view (the API).
    # If someone does need them, they can either inspect the object itself or use the include_all flag.
    if ( !$args{include_all} ) {
        delete @$as_hashref{qw(password password_hash digest_auth_hash)};
    }

    return $as_hashref;
}

=head2 overlay

Given an existing object, create a new one that has the same values for all attributes
unless they were specified in the set of new attributes. For example, if the original
value for real_name was "Jane Smith", and the new attribute set omits real_name, then
the name will remain "Jane Smith". On the other hand, if the new attribute set sets
real_name to "" (empty string), then that will replace the original value.

Arguments

  - $new_attributes - Hash ref - keys and values for any attributes to be altered.

Returns

A newly constructed Cpanel::UserManager::Record object is returned with the
resulting combination of the two sets of attributes.

=cut

sub overlay {
    my ( $self, $new_attributes ) = @_;
    'HASH' eq ref $new_attributes or Carp::croak('Needed a hash reference');

    my $outcome = _hash_merge_right_precedent( { %{$self} }, $new_attributes );

    # Passing this through the constructor instead of amending the existing object
    # makes it easier to ensure the validation works correctly.
    my $newobj = __PACKAGE__->new($outcome);

    return $newobj;
}

sub _hash_merge_right_precedent {
    my ( $orig, $overlay, $depth ) = @_;

    my $replacement = {%$orig};

    die "Application bug: Runaway recursion" if ++$depth > 9;    # Does not need to be translated

    for my $field ( keys %$overlay ) {
        if ( 'HASH' eq ref $overlay->{$field} ) {
            $replacement->{$field} = _hash_merge_right_precedent( $orig->{$field} || {}, $overlay->{$field}, $depth );
        }
        else {
            $replacement->{$field} = $overlay->{$field};
        }
    }

    return $replacement;
}

sub services {
    my ( $self, $new ) = @_;
    if ($new) {
        $self->{services} = $new;
    }

    for my $service_name ( keys %SERVICE_DEFAULTS ) {
        $self->{services}{$service_name} ||= $SERVICE_DEFAULTS{$service_name};
    }

    return $self->{services};
}

sub merge_candidates_serializable {
    my ($self) = @_;
    return [ map { 'HASH' eq ref $_ ? $_ : $_->as_hashref() } @{ $self->{merge_candidates} || [] } ];
}

sub dismissed_merge_candidates_serializable {
    my ($self) = @_;
    return [ map { 'HASH' eq ref $_ ? $_ : $_->as_hashref() } @{ $self->{dismissed_merge_candidates} || [] } ];
}

sub issues {
    my ( $self, $value ) = @_;
    if ( ref $value eq 'ARRAY' ) {
        $self->{issues} = $value;
    }
    else {
        $self->{issues} = [] if !defined $self->{issues};
    }
    return $self->{issues};
}

sub issues_serializable {
    my ($self) = @_;
    return [ map { $_->as_hashref() } @{ $self->issues || [] } ];
}

# Never let this get out of sync; require setting username and domain separately
sub full_username {
    my ($self) = @_;
    if ( length( $self->{username} ) && length( $self->{domain} ) ) {    # An additional service account
        return $self->{username} . '@' . $self->{domain};
    }
    elsif ( length( $self->{username} ) ) {                              # The cPanel user's own service account account
        return $self->{username};
    }
    else {
        return undef;                                                    # unknown
    }
}

sub has_service {
    my ( $self, $service, $state ) = @_;
    if ( !exists $SERVICE_DEFAULTS{$service} ) {
        Carp::croak("Unknown service: $service");
    }
    $self->{services} ||= {};
    if ( defined $state ) {
        $self->{services}{$service}{enabled} = $state;
    }
    return $self->{services}{$service}{enabled} || 0;
}

sub have_service_settings_changed {
    my ( $self, $other_record_obj, $service ) = @_;

    my %all_settings = map { $_ => 1 } keys( %{ $self->services->{$service} } ), keys( %{ $other_record_obj->services->{$service} } );

    # If either object has the password field defined, then we must be changing the password.
    # It couldn't have been loaded from disk, as only the password hash is stored.
    return 1 if $self->password or $other_record_obj->password;

    # There's more than one way of expressing that the service is disabled, but don't
    # treat those variations as actual changes.
    return 0 if !$self->has_service($service) && !$other_record_obj->has_service($service);

    for my $k ( sort keys %all_settings ) {
        my $my_val    = $self->services->{$service}{$k}             // '';
        my $other_val = $other_record_obj->services->{$service}{$k} // '';
        return 1 if $other_val ne $my_val;
    }

    return 0;
}

# Helper method to figure out which service a service account is for
sub service {
    my ($self) = @_;
    if ( $self->{type} eq 'service' ) {
        for my $service ( sort keys %SERVICE_DEFAULTS ) {
            return $service if $self->has_service($service);
        }
    }
    return;
}

# This is only for service accounts that are represented as record objects.
sub annotation {
    my ($self) = @_;
    if ( 'Cpanel::UserManager::AnnotationList' eq ref $self->annotation_list ) {
        return $self->annotation_list->lookup($self);
    }
    return;
}

sub _validate_boolean {
    my ( $self, $newvalue ) = @_;
    return $newvalue =~ /^[01]$/;
}

sub can_delete {
    my ($self) = my @args = @_;
    if ( @args > 1 ) {
        $self->validate_can_delete;
        die;    # unreachable because the above line will always die
    }
    my $can_delete = 'sub' eq $self->{type} || 'service' eq $self->{type};
    $can_delete &&= !$self->{special};
    return $can_delete ? 1 : 0;
}

sub as_insert {
    my ($self) = @_;

    my $record  = $self->as_hashref( include_all => 1 );
    my @to_omit = ( $self->DYNAMIC_BOOLEAN_ATTRIBUTES, $self->DYNAMIC_OTHER_ATTRIBUTES );
    delete @$record{@to_omit};

    my ( @column_names, @column_placeholders, @column_values );
    for my $col ( sort keys %$record ) {
        push @column_names,        $col;
        push @column_placeholders, '?';
        push @column_values,       $record->{$col};
    }
    my $statement = sprintf( 'INSERT INTO users (%s) VALUES (%s)', join( ',', @column_names ), join( ',', @column_placeholders ) );
    return ( $statement, \@column_values );
}

sub as_update {
    my ($self) = @_;

    my $record  = $self->as_hashref( include_all => 1 );
    my @to_omit = (
        $self->DYNAMIC_BOOLEAN_ATTRIBUTES, $self->DYNAMIC_OTHER_ATTRIBUTES,
        'guid'    # For updates, omit the guid, because it would make no sense to support changing the guid once it's already been established
    );
    delete @$record{@to_omit};

    my ( @column_names, @update_args );
    for my $col ( sort keys %$record ) {
        push @column_names, $col;
        push @update_args,  $record->{$col};
    }
    my $statement = sprintf( 'UPDATE users SET %s WHERE guid = ?', join( ', ', map { "$_ = ?" } @column_names ) );
    push @update_args, $self->guid;
    return ( $statement, \@update_args );
}

sub as_self { return shift }

sub upgrade_obj {
    return shift;
}

sub password {
    my ( $self, $new_password ) = @_;
    if ( length $new_password ) {
        $self->{password} = $new_password;

        # This same password hash type is compatible with our Email, FTP, and WebDAV services,
        # because they all use the same facility to generate and check it. However, the algorithm
        # used is configurable in /etc/sysconfig/authconfig and may vary from system to system.
        $self->password_hash( Cpanel::Auth::Generate::generate_password_hash($new_password) );

        # See Cpanel::WebDisk for another place this hash is created for digest authentication.
        my @digest_auth_components = ( $self->full_username(), Cpanel::Auth::Digest::Realm::get_realm(), $self->password() );

        Cpanel::LoadModule::load_perl_module('Digest::MD5');
        $self->digest_auth_hash( Digest::MD5::md5_hex( join ':', @digest_auth_components ) );
    }
    return $self->{password};
}

sub guid {
    my ( $self, $new ) = @_;
    if ( defined $new ) {
        $self->{guid} = $new;
    }

    # If the guid wasn't set as part of the initialization of the object (in order to retain the
    # existing stored guid), we should generate one right now.
    #
    # The username and domain are included in readable form as a visual aid for anyone trying to match
    # guids up by hand. The rest is just to ensure uniqueness. The domain will be defaulted to '' to
    # suppress warnings for any accounts (for example, the cPanel account) that lack a domain.
    if ( !defined $self->{guid} ) {
        Cpanel::LoadModule::load_perl_module('Digest::SHA');
        $self->{guid} = uc sprintf( '%s:%s:%x:%s', $self->username(), $self->domain() || '', time(), Digest::SHA::sha256_hex( join "\n", Cpanel::Hostname::gethostname(), $self->type(), int( rand 1e9 ) ) );
    }

    return $self->{guid};
}

# $_[0] is $self
# $_[1] is $service_account
sub absorb_service_account_attributes {
    my $service = $_[1]->service || die;    # It's not possible to write an error message here that would be meaningful to the end-user. If this ever happens, it's a bug, and they should open a ticket.

    # things like quota, homedir, etc.
    $_[0]->{services}{$service} = {
        %{ $_[0]->services->{$service} || {} },
        %{ $_[1]->services->{$service} }
    };

    # combine all service account issues
    return $_[0]->issues(
        [
            @{ $_[0]->issues || [] },
            @{ $_[1]->issues || [] }
        ]
    );
}

sub add_issue {
    $_[0]->{issues} = [] if !defined $_[0]->{issues};
    return push( @{ $_[0]->{issues} }, Cpanel::UserManager::Issue->new( $_[1] ) );
}

sub TO_JSON {
    return { %{ $_[0] } };
}

1;
