package Cpanel::API::CPDAVD;

# cpanel - Cpanel/API/CPDAVD.pm                    Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DAV::AddressBooks   ();
use Cpanel::DAV::Calendars      ();
use Cpanel::Args::Filter::Utils ();    # Loaded by uapi.pl or deps
use Cpanel::LoadModule          ();    # Loaded by uapi.pl or deps

=encoding utf-8

=head1 MODULE

C<Cpanel::API::CPDAVD>

=head1 DESCRIPTION

C<Cpanel::API::CPDAVD> provides various API calls related to managing calendar &
contact data for your users.

=head1 FUNCTIONS

=cut

# NOTE -- *server profile hinting* here is not really testable in a unit test,
# so it looks to be somewhat of a spook in this context.
# Other APIs do this however, and it saves code. As such, do it.
our %API = map {
    $_ => {
        needs_role       => "CalendarContact",
        needs_feature    => { match => 'all', features => [qw(caldavcarddav)] },
        worker_node_type => 'Mail',
    };
  } qw{
  add_delegate
  update_delegate
  remove_delegate
  list_delegates
  list_users
  manage_collection
  };

# This used to be used in more places back when this module was
# Cpanel::API::CCS. Probably does not need encapsulation, but leaving here
# for continuity's sake, as it ain't broke.
sub _boilerplate ( $args, $result ) {
    my ( $delegator, $delegatee ) = $args->get_length_required(qw{delegator delegatee});
    my $calendar = $args->get_length_required(qw{calendar});
    die "Delegator cannot be the same as delegatee" if $delegator eq $delegatee;
    my ($readonly) = $args->get('readonly');

    my %arg_hash = (
        'delegator' => $delegator,
        'delegatee' => $delegatee,
        'calendar'  => $calendar,
        'readonly'  => $readonly,
    );

    return ( \%arg_hash, $result );
}

# Check some basic stuff to help ensure malicious actors are not adding bad bits
sub _sanity_check {
    my ( $type, $string ) = @_;
    if ( $type eq 'path' ) {
        if ( $string =~ m/[\[\]\r\x00\n\/]/ ) {
            die "Invalid characters detected.";
        }
    }
    elsif ( $type eq 'user_or_email' ) {

        # For email addresses
        if ( grep /\@/, $string ) {
            require Cpanel::Validate::EmailRFC;
            if ( !Cpanel::Validate::EmailRFC::is_valid($string) ) {
                die "Invalid email.";
            }
        }
        else {    # For system users
            require Cpanel::Validate::Username::Core;
            if ( !Cpanel::Validate::Username::Core::is_valid($string) ) {
                die "Invalid user.";
            }
        }
    }
    else {
        die "_sanity_check called on unknown type.";    # help prevent this sub from being used uselessly
    }
    return 0;
}

sub _manage {
    my ( $action, @args_and_result ) = @_;
    my ( $args,   $result )          = _boilerplate(@args_and_result);

    _validate_path_or_die( $args->{$_} ) for qw(calendar delegator delegatee);

    # Block sharing of other webmail accounts by a webmail account, etc.
    if ( $Cpanel::authuser ne $Cpanel::user && $args->{'delegator'} ne $Cpanel::authuser ) {
        die "Webmail accounts are not allowed to share other webmail users' calendars.";
    }

    # Do some basic sanity checking on input. Most of this is wide open due to non-ascii language characters, and while
    # we are only truly limited to blocking / due to this being a file system path, we block a few others in the API call
    # to help prevent abuse
    _sanity_check( 'path',          $args->{'calendar'} );
    _sanity_check( 'user_or_email', $args->{'delegatee'} );
    _sanity_check( 'user_or_email', $args->{'delegator'} );

    require Cpanel::DAV::CaldavCarddav;
    my $cd_obj     = Cpanel::DAV::CaldavCarddav->new( acct_homedir => $Cpanel::homedir, sys_user => $Cpanel::authuser );
    my $sharing_hr = $cd_obj->load_sharing();

    # Use defaults and coercion to prevent any possible errors here
    $args->{'readonly'} //= 1;
    my $perms = $args->{'readonly'} + 0 == 0 ? 'r,w' : 'r';

    if ( $action eq 'DELETE' ) {
        die "Delegate does not exist" if !exists( $sharing_hr->{ $args->{delegator} } );
        die "Delegate does not exist" if !exists( $sharing_hr->{ $args->{delegator} }{ $args->{calendar} } );
        die "Delegate does not exist" if !exists( $sharing_hr->{ $args->{delegator} }{ $args->{calendar} }{ $args->{delegatee} } );
        delete $sharing_hr->{ $args->{delegator} }{ $args->{calendar} }{ $args->{delegatee} };
        delete $sharing_hr->{ $args->{delegator} }{ $args->{calendar} } if !keys( %{ $sharing_hr->{ $args->{delegator} }{ $args->{calendar} } } );
        delete $sharing_hr->{ $args->{delegator} }                      if !keys( %{ $sharing_hr->{ $args->{delegator} } } );
    }
    else {
        $sharing_hr->{ $args->{delegator} } ||= {};
        $sharing_hr->{ $args->{delegator} }{ $args->{calendar} } ||= {};
        $sharing_hr->{ $args->{delegator} }{ $args->{calendar} }{ $args->{delegatee} } = $perms;
    }

    # Should die if it fails
    $cd_obj->save_sharing($sharing_hr);

    return 1;
}

=head2 add_delegate

Add a delegate

=cut

# Yet more legacy of Cpanel::API::CCS. Were I to do it today, I'd have done
# it in one API method with the below as args, but meh. May as well maintain
# compatibility with the old CCS UAPI since it's "free" to do so here.
sub add_delegate {
    return _manage( 'INSERT', @_ );
}

=head2 update_delegate

Update a delegate

=cut

sub update_delegate {
    return _manage( 'UPDATE', @_ );
}

=head2 remove_delegate

Remove a delegate

=cut

sub remove_delegate {
    return _manage( 'DELETE', @_ );
}

=head2 list_delegates

List delegates

=cut

sub list_delegates {
    my ( $args, $result ) = @_;

    require Cpanel::DAV::CaldavCarddav;
    if ( Cpanel::DAV::CaldavCarddav::is_over_quota($Cpanel::authuser) ) {
        $result->error("Account is over quota, aborting delegation operations");
        return 0;
    }

    my $cd_obj     = Cpanel::DAV::CaldavCarddav->new( acct_homedir => $Cpanel::homedir, sys_user => $Cpanel::authuser );
    my $sharing_hr = $cd_obj->load_sharing();

    my @delegation_array;
    foreach my $delegator ( keys( %{$sharing_hr} ) ) {
        my $metadata_path = "$cd_obj->{acct_homedir}/.caldav/$delegator/.metadata";
        my $metadata_hr   = $cd_obj->{'metadata'}->load($metadata_path);
        foreach my $calendar ( keys( %{ $sharing_hr->{$delegator} } ) ) {
            my $cal_name = $metadata_hr->{$calendar}{displayname} || "N/A";
            foreach my $delegatee ( keys( %{ $sharing_hr->{$delegator}{$calendar} } ) ) {
                next if ( $Cpanel::user ne $Cpanel::authuser && $delegator ne $Cpanel::authuser );
                push @delegation_array, {
                    'delegator' => $delegator,
                    'delegatee' => $delegatee,
                    'calendar'  => $calendar,
                    'calname'   => $cal_name,
                    'readonly'  => $sharing_hr->{$delegator}{$calendar}{$delegatee} eq 'r' ? 1 : 0,
                };
            }
        }
    }

    $result->data( \@delegation_array );
    return 1;

}

=head2 list_users

List CalDAV/CardDAV users.

Much of this was not in Cpanel::API::CCS but instead in Cpanel::CCS::Userdata.
Sub back then was "list_pops_with_extra_sauce"... in this case the "sauce"
being metadata about the users relevant to the calendarserver.

=cut

sub list_users {
    my ( $args, $result ) = @_;

    require Cpanel::Email::Accounts;
    require Cpanel::Validate::EmailLocalPart;
    require Cpanel::DAV::CaldavCarddav;

    my $cd_obj = Cpanel::DAV::CaldavCarddav->new( acct_homedir => $Cpanel::homedir, sys_user => $Cpanel::authuser );
    my ( $untrusted_pops_info, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db(
        'event'       => 'fetch',
        'no_disk'     => 1,
        'no_validate' => 1,
    );
    $_manage_err = $@ if $@;
    warn $_manage_err if $_manage_err;

    my $filters = $args->filters();

    # Important: Only use the untrusted data as a reference for the list of local parts,
    # not for the list of domains.
    my %trusted_pops_hash;
    no warnings qw{once};    # XXX $Cpanel::CPDATA{DOMAINS}
    for my $domain ( keys %$untrusted_pops_info ) {
        next if ( !grep $domain, @{ $Cpanel::CPDATA{DOMAINS} } );
        for my $acct ( keys %{ $untrusted_pops_info->{$domain}{accounts} || {} } ) {
            next unless ( length $acct && $acct !~ tr/a-zA-Z0-9!#\$\-=?^_{}~//c ) || Cpanel::Validate::EmailLocalPart::is_valid($acct);
            my $email = "${acct}\@${domain}";

            # Use filtering if you want that
            next if scalar(@$filters) && !Cpanel::Args::Filter::Utils::check_value_for_column_versus_filters( $email, 'user', $filters );

            # Ok, do stuff
            my $calendar_collections_hr = $cd_obj->get_collections_for_user($email);

            # Remove potentially large and unwanted metadata
            foreach my $collection ( keys %{$calendar_collections_hr} ) {
                delete $calendar_collections_hr->{$collection}{'calendar-timezone'};
            }

            $trusted_pops_hash{"${acct}\@${domain}"} = $calendar_collections_hr;
        }
    }

    # Add the cpuser as well while we are at it
    if ( !scalar(@$filters) || Cpanel::Args::Filter::Utils::check_value_for_column_versus_filters( $Cpanel::user, 'user', $filters ) ) {
        $trusted_pops_hash{$Cpanel::user} = $cd_obj->get_collections_for_user($Cpanel::user);
    }

    # For Webmail, we need to show other users so that the sharing interface can function, but omit
    # collection names and descriptions for everyone else, as this could be considered sensitive
    # information not normally available to these users.
    if ( $Cpanel::authuser ne $Cpanel::user ) {
        for my $who ( sort keys %trusted_pops_hash ) {
            $trusted_pops_hash{$who} = {} unless $who eq $Cpanel::authuser;
        }
    }

    $result->data( \%trusted_pops_hash );

    return 1;
}

# So, now we get on to the brand new, non-CCS code. "Create Calendars, etc."
# CUD instead of CRUD in this case as rename makes no sense in this context.
# Why bother changing the path on disk once there? That would only break
# clients.
my @valid_actions = qw{create update delete};
my $manage_sr     = sub ( $collection_type, $args ) {
    die "Collection type not supported: $collection_type"
      if !grep { $collection_type eq $_ } qw{calendar addressbook};
    my $acct = lc( $args->get_length_required('account') );

    # Check that acct exists. If it is the current REMOTE_USER, we can be
    # assured that the user, in fact, exists in almost all circumstances.
    # XXX Also, yay, "once"
    no warnings qw{once};
    if ( $acct ne $ENV{'REMOTE_USER'} && $acct ne $Cpanel::authuser ) {

        # Access control: You are attempting to manage an account other than your own (acct ne remote user), but you are a virtual account (remote user contains @). Not good.
        if ( index( $ENV{'REMOTE_USER'}, '@' ) > 0 ) {
            die "No access for account '$acct'";
        }

        # You are attempting to manage an account other than your own (acct ne remote user), but the account being managed is not virtual (acct does not contain @). Makes no sense.
        if ( index( $acct, '@' ) eq -1 ) {
            require Data::Dumper;
            die "Account being managed appears incorrect. Info:\n" . Data::Dumper::Dumper(
                {
                    'REMOTE_USER'       => $ENV{'REMOTE_USER'},
                    '$Cpanel::authuser' => $Cpanel::authuser,
                    '$acct'             => $acct,
                }
            );
        }

        my ( $localpart, $domain, @more ) = split /\@/, $acct;
        die "Nonsensical email address '$acct'\n" if @more;

        my $quoted_acct = quotemeta $acct;
        my ( $pops, $err ) = Cpanel::Email::Accounts::manage_email_accounts_db(
            'event'   => 'fetch',
            'no_disk' => 1,
            'regex'   => "^${quoted_acct}\$",
        );
        die "Can't fetch email accounts db: $err" if ( !$pops && defined $err );

        die "Nonexistent account: $acct" if !$pops->{$domain}{'accounts'}{$localpart};    # This is NOT a form of access control, only an existence check.
    }

    # Path can be blank. Then it becomes autogenerated. IF however they
    # pass one in, validate it.
    my $path = $args->get('path');
    _validate_path_or_die($path) if length $path;

    my $action = lc( $args->get_length_required('action') );

    # XXX TODO replace dies with localized Exception usage
    die "Invalid action passed to manage_collection"
      if !grep { $action eq $_ } @valid_actions;

    # I'm using a UUID here to ensure uniqueness of the path, though I'm not
    # opposed to using something shorter so long as it satisfies the same
    # requirement.
    my %defaults = (
        'create' => {
            'path' => sub {
                require Cpanel::UUID;
                return $collection_type . '-' . Cpanel::UUID::random_uuid();
            },
        },
    );
    my %required = (
        'create' => ['name'],
        'update' => ['path'],
        'delete' => ['path'],
    );
    my %optional = (
        'create' => [ 'path', 'calendar-color', 'description' ],
    );
    my %at_least_one = (
        'update' => [ 'name', 'description', 'calendar-color' ],
    );

    # Unfortunately you must assign to temp HR to hint the parser here to not
    # think otherwise valid syntax is valid syntax.
    # Hopefully this is optimized away in the compiler, but I have my doubts.
    my %real_args = (
        { map { $_ => $defaults{$action}->{$_}->() } keys( %{ $defaults{$action} } ) }->%*,
        { map { $_ => $args->get_length_required($_) } @{ $required{$action} } }->%*,
        { map { $_ => $args->get($_) } grep { $args->get($_) } @{ $at_least_one{$action} } }->%*,
        { map { $_ => $args->get($_) } grep { $args->get($_) } @{ $optional{$action} } }->%*,
    );
    die "Need at least one of [ " . join( ", ", @{ $at_least_one{$action} } ) . " ] passed in for $action!"
      if ( @{ $at_least_one{$action} } && !grep { $real_args{$_} } @{ $at_least_one{$action} } );

    require Cpanel::DAV::Principal;
    my $principal = Cpanel::DAV::Principal->get_principal($acct);
    return ( $action, $principal, map { $real_args{$_} } qw{path name description calendar-color} );
};

=head2 manage_collection

Perform an operation on a collection (calendar or address book). The operation can be create, update, or delete.

=cut

sub manage_collection ( $args, $result ) {
    my $coll_type = $args->get_length_required("collection_type");
    my ( $action, $principal, $path, $name, $description, $color ) = $manage_sr->( $coll_type, $args );
    my %sub_map = (
        'calendar' => {
            'namespace' => 'Cpanel::DAV::Calendars',
            'create'    => sub { return Cpanel::DAV::Calendars::create_calendar( $principal, $path, $name, $description, $color ); },
            'delete'    => sub { return Cpanel::DAV::Calendars::remove_calendar_by_path( $principal, $path ); },
            'update'    => sub { return Cpanel::DAV::Calendars::update_calendar_by_path( $principal, $path, $name, $description, $color ); },
        },
        'addressbook' => {
            'namespace' => 'Cpanel::DAV::AddressBooks',
            'create'    => sub { return Cpanel::DAV::AddressBooks::create_addressbook( $principal, $path, $name, $description ); },
            'delete'    => sub { return Cpanel::DAV::AddressBooks::remove_addressbook_by_path( $principal, $path ); },
            'update'    => sub { return Cpanel::DAV::AddressBooks::update_addressbook_by_path( $principal, $path, $name, $description ); },
        }
    );

    # Set the (optional) description to the (required) collection name if the description is empty.
    if ( !length($description) ) {
        $description = $name;
    }

    # Second chance to die "hey this isn't implemented yet."
    # Presumably you'd add the namespace when it's supported, even if all
    # all actions aren't yet implemented, so, I don't check for that.
    die "Unimplemented" if ( !$sub_map{$coll_type} || !$sub_map{$coll_type}->{$action} );
    Cpanel::LoadModule::load_perl_module( $sub_map{$coll_type}->{'namespace'} );
    my $ret = $sub_map{$coll_type}->{$action}->();

    # $result->raw_error doesn't actually set the raw error.
    # Dying does so let's do that instead.
    if ( !$ret->{'meta'}{'ok'} ) {
        $result->raw_error( $ret->{'meta'}{'text'} );
        return 0;
    }

    $result->raw_message( $ret->{'meta'}{'text'} );
    return 1;
}

sub _validate_path_or_die {
    my ($path) = @_;
    die "Invalid path '$path'\n" if $path =~ m{\.\.};
    return 1;
}

1;
