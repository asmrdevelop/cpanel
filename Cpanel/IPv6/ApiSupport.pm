package Cpanel::IPv6::ApiSupport;

# cpanel - Cpanel/IPv6/ApiSupport.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Userdomains             ();
use Cpanel::CPAN::Net::IP           ();
use Cpanel::Logger                  ();
use Cpanel::AcctUtils::Account      ();
use Cpanel::IPv6::Utils             ();
use Cpanel::IPv6::User              ();
use Cpanel::IPv6::UserDataUtil      ();
use Cpanel::IPv6::ApacheUtil        ();
use Cpanel::IPv6::Normalize         ();
use Cpanel::Ips::V6                 ();
use Cpanel::CachedDataStore         ();
use Cpanel::Locale                  ();
use Cpanel::Exception               ();
use Cpanel::SPF                     ();

my $logger = Cpanel::Logger->new();
my $locale;

#
# Enable IPv6 for a user account
# params:
#       users - username(s) for the account (comma delimited)
#       range_name - ip range from which to draw the ip(s)
#
sub enable_ipv6_for_user {
    my ( $users, $range_name ) = @_;

    my $user_cnt = $users =~ tr/\,//;
    $user_cnt++;

    $locale ||= Cpanel::Locale->get_handle();

    # Validate range name
    if ( !Cpanel::IPv6::Utils::validate_range_name($range_name) ) {
        return ( 0, $locale->maketext( 'Range does not exist: [_1]', $range_name || '' ) );
    }

    $users =~ s/\s+//g;
    my @user_list = split( /\,/, $users );

    my %failures;
    my $fail_cnt = 0;
    my %ipv6_address_list;

    foreach my $user (@user_list) {

        # Skip any users that are already enabled to prevent errors on the frontend [ TP 14596 ]
        my $addy = Cpanel::IPv6::User::get_user_ipv6_address($user);
        if ( Cpanel::CPAN::Net::IP::ip_is_ipv6($addy) ) { next; }

        my ( $ret, $data );
        eval { ( $ret, $data ) = enable_ipv6_for_single_user( $user, $range_name ); };

        # Convert exception to the same has having returned an error
        if ($@) {
            $ret  = 0;
            $data = Cpanel::Exception::get_string($@);
        }

        if ($ret) {

            # success, add the ipv6 address to our list
            $ipv6_address_list{$user} = $data;
        }
        else {
            # failure, assign the user key the error message
            $fail_cnt++;
            $failures{$user} = $data;
            $logger->warn($data);
        }
    }

    if ( $fail_cnt == @user_list ) {
        return ( 0, $locale->maketext( "The system encountered the following [numerate,_1,error,errors] while it tried to enable IPv6 for the selected users: [list_and_quoted,_2].", $fail_cnt, [ values %failures ] ) );
    }

    # Return success if the call itself gets to the end, we will return individual failures inside the returned data
    return ( 1, { 'ipv6' => \%ipv6_address_list, 'failures' => \%failures, 'fail_cnt' => $fail_cnt } );
}

#
# Enable ipv6 for a single account
#
sub enable_ipv6_for_single_user {
    my ( $user, $range_name ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    $range_name //= '';

    # validate account
    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        return ( 0, $locale->maketext( "The “[_1]” account does not exist.", $user ) );
    }

    # We're going to use these a lot
    my ( $ret, $msg, $data );

    # Figure out if it already has been set up for ipv6
    ( $ret, $data ) = Cpanel::IPv6::User::get_user_ipv6_address($user);
    return ( 0, $locale->maketext( "The “[_1]” account already has an IPv6 address: [_2]", $user, $data || '' ) ) if $ret;

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load_or_die($user);

    require Cpanel::LinkedNode::Worker::GetAll;
    if ( Cpanel::LinkedNode::Worker::GetAll::get_all_from_cpuser($cpuser_data) ) {
        return ( 0, $locale->maketext( "The “[_1]” account is a distributed account. Distributed accounts cannot use [asis,IPv6].", $user ) );
    }

    # Set the users ip address range
    ( $ret, $msg ) = Cpanel::IPv6::Utils::set_users_range( $user, $range_name );
    return ( $ret, $msg ) unless $ret;

    my $ipv6address;
    if ( $range_name ne Cpanel::IPv6::Utils::shared_ipv6_key() ) {
        ( $ret, $ipv6address ) = _get_next_available_ipv6( $user, $range_name );
    }
    else {
        # we'll use the shared IP only if it's set #
        my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
        if ( !$wwwacct_ref->{'ADDR6'} ) {
            Cpanel::IPv6::Utils::remove_user_from_single_range( $user, $range_name );
            return ( 0, $locale->maketext( "You cannot assign a shared IPv6 address to “[_1]” because you have not configured a shared IPv6 address.", $user ) );
        }
        if ( !Cpanel::Ips::V6::validate_ipv6( $wwwacct_ref->{'ADDR6'} ) ) {
            Cpanel::IPv6::Utils::remove_user_from_single_range( $user, $range_name );
            return ( 0, $locale->maketext( "The configured shared IPv6 address does not use a valid format (IPv6/CIDR): [_1].", $wwwacct_ref->{'ADDR6'} ) );
        }
        ( $ret, $ipv6address ) = ( 1, $wwwacct_ref->{'ADDR6'} );
    }

    # If getting a new IP failed, we need to remove the user from that range
    if ( !$ret ) {
        Cpanel::IPv6::Utils::remove_user_from_single_range( $user, $range_name );
        return ( 0, $locale->maketext( "Error while enabling IPv6 for “[_1]”: [_2]", $user, $ipv6address ) );
    }

    # Make sure we actually found a valid ip address
    if ( !Cpanel::CPAN::Net::IP::ip_is_ipv6($ipv6address) ) {
        return ( 0, $locale->maketext('The system was unable to find a valid IPv6 address.') );
    }

    # At this point we have a valid IPv6 address, and it is bound
    $logger->info( $locale->maketext( "Adding the “[_1]” IPv6 address to the “[_2]” account.", $ipv6address, $user ) );

    # Add to the user data
    ( $ret, $msg ) = Cpanel::IPv6::UserDataUtil::add_ipv6_for_user( $user, $ipv6address, 1 );
    return ( 0, $locale->maketext( "The system was unable to update the user data for “[_1]”: [_2]", $user, $msg ) ) unless $ret;

    # Update the named config
    ( $ret, $msg ) = Cpanel::IPv6::Utils::update_named_config( $user, $ipv6address, 'enable' );
    return ( 0, $locale->maketext( "The system was unable to update the named config for “[_1]”: [_2]", $user, $msg ) ) unless $ret;

    # Update the apache config
    ( $ret, $msg ) = Cpanel::IPv6::ApacheUtil::add_ipv6_for_user($user);
    return ( 0, $locale->maketext( "The system was unable to update the Apache configuration for “[_1]”: [_2]", $user, $msg ) ) unless $ret;

    # Update mail configuration
    {
        local $@;
        $ret = eval { Cpanel::Userdomains::updateuserdomains('--force'); 1; };
        return ( 0, $locale->maketext( "The system was unable to update the mail configuration for “[_1]”: [_2]", $user, $@ ) ) if $@;
    }

    # update SPF records #
    if ( Cpanel::SPF::has_spf( 'user' => $user ) ) {
        require Cpanel::SPF::Update;

        # setup_spf for the entire user will override existing records
        # we should only call it when setting up for the first time
        ( $ret, $msg ) = Cpanel::SPF::Update::update_spf_records( 'users' => [$user] );
        return ( 0, $locale->maketext( "The system was unable to update SPF records for “[_1]”: [_2]", $user, $msg ) )
          unless $ret;
    }

    # Yay! We made it!
    return ( 1, $ipv6address );
}

#
# Disable IPv6 for a user accounts
# params:
#       user - username(s) for the account (space delimited)
#
sub disable_ipv6_for_user {
    my ($users) = @_;

    my $user_cnt = $users =~ tr/\,//;
    $user_cnt++;

    $locale ||= Cpanel::Locale->get_handle();

    $users =~ s/\s+//g;
    my @user_list = split( /\,/, $users );

    my $fail_cnt = 0;
    my %failures;

    foreach my $user (@user_list) {

        # Skip any users that are already disabled to prevent errors on the frontend [ TP 14596 ]
        my $addy = Cpanel::IPv6::User::get_user_ipv6_address($user);
        if ( $addy eq Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() ) { next; }

        my ( $ret, $data );
        eval { ( $ret, $data ) = disable_ipv6_for_single_user($user); };

        # Convert exception to the same has having returned an error
        if ($@) {
            $ret  = 0;
            $data = Cpanel::Exception::get_string($@);
        }

        if ( !$ret ) {

            # failure, add to our list of error messages
            $fail_cnt++;
            $failures{$user} = $data;
            $logger->warn($data);
        }
    }

    # If no failures, return OK
    if ( !$fail_cnt ) {
        return ( 1, $locale->maketext('OK') );
    }

    # If we are only working with one user, return 0 for failure to enable, otherwise return 1 along with a list of users/failures/successes
    return ( 1, { 'failures' => \%failures, 'fail_cnt' => $fail_cnt } );

}

#
# Disable IPv6 for a user account
# params:
#       user - username for the account
#
sub disable_ipv6_for_single_user {
    my ($user) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    # validate account
    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        return ( 0, $locale->maketext( "The “[_1]” account does not exist.", $user ) );
    }

    $logger->info( $locale->maketext( "Removing IPv6 from account: [_1]", $user ) );

    # We're going to use these a lot
    my ( $ret, $msg );

    # Get the IPv6 address for the account, if dedicated we may need to unbind it
    ( $ret, my $ipv6address ) = Cpanel::IPv6::User::get_user_ipv6_address($user);

    # Determine whether we are going to need to remove that ip address
    # Log any irregularities that are found in the process of doing this
    my $unbind = 0;
    if ( !$ret or !Cpanel::CPAN::Net::IP::ip_is_ipv6($ipv6address) ) {

        # No valid ipv6 address found, that is odd, so log this
        $logger->warn( $locale->maketext( "The “[_1]” account does not appear to have an assigned IPv6 address. The system will now remove any other IPv6 configuration information that is with the account.", $user ) );
    }
    else {
        $unbind = 1;
    }

    # Error/Success values we will return
    # We want to attempt all the removal steps even if some fail
    # We'll 'and' all the return codes so that a failure of one means a failure of all
    # And, we'll concatenate all the error messages & return them if there are failures
    my $success = 1;
    my $messages;

    # Update the range config to add the IP to the "reclaimed" list after finding range
    ( $ret, my $range_config ) = Cpanel::IPv6::Utils::load_range_config();

    # Get range for user
    ( $ret, my $range_name ) = Cpanel::IPv6::Utils::get_range_for_user_from_range_config($user);
    if ( $ret && $range_name ne Cpanel::IPv6::Utils::shared_ipv6_key() ) {
        Cpanel::IPv6::Utils::add_ip_to_reclaimed_list( $ipv6address, $range_name );
    }
    else {
        $messages .= $locale->maketext( "Unable to determine range for user: [_1]", $user );
    }

    # Remove the ipv6 address info from the account's userdata
    ( $ret, $msg ) = Cpanel::IPv6::UserDataUtil::remove_ipv6_for_user($user);
    $success &= $ret;
    $messages .= $locale->maketext( "Unable to update user data: [_1]", $msg ) . "\n" unless $ret;

    # Update the named config
    ( $ret, $msg ) = Cpanel::IPv6::Utils::update_named_config( $user, undef, 'disable' );
    $success &= $ret;
    $messages .= $locale->maketext( "Unable to update named config: [_1]" . "\n", $msg ) unless $ret;

    # Remove from apache config
    ( $ret, $msg ) = Cpanel::IPv6::ApacheUtil::remove_ipv6_for_user($user);
    $success &= $ret;
    $messages .= $locale->maketext( "Unable to update apache config: [_1]", $msg ) . "\n" unless $ret;

    # Update mail configuration
    {
        local $@;
        $ret = eval { Cpanel::Userdomains::updateuserdomains('--force'); 1; };
        return ( 0, $locale->maketext( "The system was unable to update the mail configuration for “[_1]”: [_2]", $user, $@ ) ) if $@;
    }

    # update SPF records #
    if ( Cpanel::SPF::has_spf( 'user' => $user ) ) {
        require Cpanel::SPF::Update;

        # setup_spf for the entire user will override existing records
        # we should only call it when setting up for the first time
        ( $ret, $msg ) = Cpanel::SPF::Update::update_spf_records( 'users' => [$user] );
        return ( 0, $locale->maketext( "The system was unable to update SPF records for “[_1]”: [_2]", $user, $msg ) )
          unless $ret;
    }

    # Unbind the ip address if it was dedicated
    if ($unbind) {
        my $range_ref = $range_config->{$range_name};
        if ( !$range_ref || ref $range_ref ne ref {} ) {
            $success = 0;
            $messages .= $locale->maketext( "Invalid range name: [_1]", $range_name );
        }
        elsif ( $range_name ne Cpanel::IPv6::Utils::shared_ipv6_key() ) {

            # we'll need the range's CIDR to remove it from the interface (without the CIDR, iproute2 tools give a deprecation warning) #
            my $cidr = Cpanel::CPAN::Net::IP->new( ( $range_ref->{'first'} || 1 ) . ' - ' . ( $range_ref->{'last'} || 1 ) );
            $ipv6address .= '/' . $cidr->prefixlen() if $cidr and $cidr->prefixlen();

            ( $ret, $msg ) = Cpanel::IPv6::Utils::add_or_delete_ipv6_address( 'delete', $range_name, $range_ref, $ipv6address );
            $success &= $ret;
            $messages .= $locale->maketext( "Unable to delete ip: [_1]", $msg ) . "\n" unless $ret;
        }
    }

    # Remove the user from any ip range they may be in
    ( $ret, $msg ) = Cpanel::IPv6::Utils::remove_users_range($user);
    $success &= $ret;
    $messages .= $locale->maketext( "Unable to remove user from ip range: [_1]", $msg ) . "\n" unless $ret;

    # We're done, return success if everything passed
    # return our collection of messages if there were failures
    return ( $success, $success ? $locale->maketext("OK") : $locale->maketext("There were the following errors:") . "\n" . $messages );
}

#
# Get the next available ipv6 address to dedicate for a user
#
sub _get_next_available_ipv6 {
    my ( $user, $range_name ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    # protect against callers assuming the shared IP can give more IPs #
    return ( 0, $locale->maketext('The shared IP address cannot enumerate more IP addresses.') )
      if $range_name eq Cpanel::IPv6::Utils::shared_ipv6_key();

    # used a bunch
    my ( $ret, $msg );

    # we'll need the range configuration here because it's used in several subs #
    return ( 0, $locale->maketext("No range name supplied") ) unless $range_name;
    my $range_config;
    ( $ret, $range_config ) = Cpanel::IPv6::Utils::load_range_config();
    my $range_ref = $range_config->{$range_name};
    return ( 0, $locale->maketext( "Invalid range name: [_1]", $range_name ) ) unless ref $range_ref eq ref {};

    # Get ip from the user's range
    ( $ret, my $was_reclaimed, my $nextaddress, my $cidr ) = Cpanel::IPv6::Utils::get_next_available_ipv6_from_range( $range_name, $range_config );

    # If we still haven't found it in the server group, error out
    if ( !$ret ) {
        return ( 0, $locale->maketext('This IPv6 address range does not have any IPv6 addresses available. All IPv6 addresses in this range have been assigned to users.') );
    }
    if ( !Cpanel::CPAN::Net::IP::ip_is_ipv6($nextaddress) ) {
        return ( 0, $locale->maketext('Invalid IPv6 address') );
    }

    # Ensure we can bind IP to server before futzing with config files
    ( $ret, $msg ) = Cpanel::IPv6::Utils::add_or_delete_ipv6_address( 'add', $range_name, $range_ref, "$nextaddress/$cidr" );
    return ( 0, $locale->maketext( "The “[_1]” address cannot be bound: [_2]", "$nextaddress/$cidr", $msg ) ) unless $ret;

    # If we are using a reclaimed IP, do not alter the mostrecent address pointer
    #
    if ( $was_reclaimed == 0 ) {

        # Update the range files to signify that the address has been used
        my %newmostrecent;
        $newmostrecent{$range_name}{'mostrecent'} = $nextaddress;
        ( $ret, $msg ) = Cpanel::IPv6::Utils::save_range( \%newmostrecent );
        return ( 0, $locale->maketext( "Unable to update the IPv6 range files: [_1]", $msg ) ) unless $ret;
    }
    return ( 1, $nextaddress );
}

#
# Add a new ipv6 range
#
sub ipv6_range_add {
    my ($args) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my %new_range;

    # Length validation
    $args->{'name'} = trim_range_name( $args->{'name'} );
    $args->{'note'} = trim_range_note( $args->{'note'} );

    return ( 0, $locale->maketext('Invalid Range Name') ) unless $args->{'name'};

    return ( 0, $locale->maketext('Invalid Range') ) unless exists $args->{'range'};

    my ( $ret, $existing_range_ref ) = Cpanel::IPv6::Utils::load_range_config();

    return ( 0, $locale->maketext('Range Already Exists') ) if exists $existing_range_ref->{ $args->{'name'} };

    # Enabled defaults to true
    $args->{'enabled'} = 1 unless exists $args->{'enabled'};

    # Normalize
    $args->{'enabled'} = $args->{'enabled'} ? 1 : 0;

    # Figure out the first/last/most-recent from the range CIDR string
    my $ip_range = Cpanel::CPAN::Net::IP->new( $args->{'range'}, 6 );
    return ( 0, $locale->maketext("Invalid IPv6 range") ) unless $ip_range;

    # Check to see if the range overlaps with any other enabled ranges, if not a reserved range itself
    if ( $args->{'enabled'} == 1 ) {
        my $overlapped = Cpanel::IPv6::Utils::range_overlaps_existing( $ip_range, 1, $existing_range_ref );
        return ( 0, $locale->maketext( "The range overlaps with another existing range: [_1]", $overlapped ) ) if $overlapped;
    }

    my $first_ip = $ip_range->ip();
    my $last_ip  = $ip_range->last_ip();

    $new_range{ $args->{'name'} } = {
        'first'       => $first_ip,
        'last'        => $last_ip,
        'mostrecent'  => undef,
        'enabled'     => $args->{'enabled'},
        'owner'       => $ENV{'USER'} || 'root',
        'note'        => $args->{'note'},
        'range_users' => [],
    };

    ( $ret, my $msg ) = Cpanel::IPv6::Utils::save_range( \%new_range );
    if ($ret) {
        return ( 1, $locale->maketext('OK') );
    }
    else {
        return ( 0, $msg );
    }
}

#
# Change special values for a range
#
sub ipv6_range_edit {
    my ($args) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    # If no name has been specified, then nothing to do
    return ( 0, $locale->maketext('Invalid Range Name') ) unless $args->{'name'};

    # protect against callers trying to edit the shared IP here #
    return ( 0, $locale->maketext(q{This function cannot edit the main shared IP address. Use [asis,WHM]’s Basic cPanel [output,amp] WHM Setup interface (Home » Server Configuration » Basic cPanel [output,amp] WHM Setup) to configure the shared IPv6 address.}) )
      if $args->{'name'} eq Cpanel::IPv6::Utils::shared_ipv6_key();

    # Only update the note or the name if the appropriate options have been supplied
    # This differs from, say, intentionaly supplying an empty note in order to erase the note
    my $update_name = ( exists $args->{'new_name'} ) ? 1 : 0;
    my $update_note = ( exists $args->{'note'} )     ? 1 : 0;

    # Length validation
    $args->{'new_name'} = trim_range_name( $args->{'new_name'} );
    $args->{'note'}     = trim_range_note( $args->{'note'} );

    # If they want to change the name, make sure they are
    # changing it to something valid that survived trimming
    return ( 0, $locale->maketext('Invalid new name') ) if ( $update_name && !$args->{'new_name'} );

    # If they specified neither name nor note, then nothing to do
    return ( 0, $locale->maketext('Neither a new name nor a new note was specified; nothing to do') ) unless $update_name || $update_note;

    # Now we can get the range config
    my ( $ret, $range_config ) = Cpanel::IPv6::Utils::load_range_config();

    # Get the one we are interested in
    my $range = $range_config->{ $args->{'name'} };
    return ( 0, $locale->maketext( "Invalid range name: [_1]", $args->{'name'} ) ) unless ( ref $range eq 'HASH' );

    # The name for the range when we save it
    my $name_to_save = $update_name ? $args->{'new_name'} : $args->{'name'};

    # If we're updating the note, change it here
    $range->{'note'} = $args->{'note'} if $update_note;

    # If we are changing the name, delete the original range
    if ($update_name) {
        if ( !delete $range_config->{ $args->{'name'} } ) {
            return ( 0, $locale->maketext( "Unable to delete range from hash: [_1]", $! ) );
        }

        # Save the config with the old name deleted
        my $ret = Cpanel::CachedDataStore::store_ref( $Cpanel::IPv6::Utils::range_data_file_path, $range_config );
        return ( 0, $locale->maketext( "Problem saving modified range: [_1]", $! ) ) unless $ret;
    }

    # Save our changed range
    ( $ret, my $msg ) = Cpanel::IPv6::Utils::save_range( { $name_to_save => $range } );
    if ($ret) {
        return ( 1, $locale->maketext('OK') );
    }
    else {
        return ( 0, $msg );
    }
}

#
# Remove an ipv6 range
#
sub ipv6_range_remove {
    my ($name) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    if ( !$name ) {
        return ( 0, $locale->maketext('No range name given') );
    }

    # protect against callers trying to remove the shared IP here #
    return ( 0, $locale->maketext(q{This function cannot remove the main shared IP address. Use [asis,WHM]’s Basic cPanel [output,amp] WHM Setup interface (Home » Server Configuration » Basic cPanel [output,amp] WHM Setup) to configure the shared IPv6 address.}) )
      if $name eq Cpanel::IPv6::Utils::shared_ipv6_key();

    my ( $ret, $existing_range_ref ) = Cpanel::IPv6::Utils::load_range_config();

    return ( 0, $locale->maketext('The given range name does not exist') ) unless exists $existing_range_ref->{$name};

    return ( 0, $locale->maketext('The range is still in use') ) if scalar @{ $existing_range_ref->{$name}{'range_users'} };

    if ( !delete $existing_range_ref->{$name} ) {
        return ( 0, $locale->maketext( "Unable to delete range: [_1]", $! ) );
    }

    # Save our modified range config
    if ( Cpanel::CachedDataStore::store_ref( $Cpanel::IPv6::Utils::range_data_file_path, $existing_range_ref ) ) {
        return ( 1, $locale->maketext('Range removed') );
    }
    else {
        return ( 0, $locale->maketext( "Problem saving modified range: [_1]", $! ) );
    }
}

#
# Get a list of all the ipv6 ranges and their attributes
#
sub ipv6_range_list {
    my ( $ret, $range_data_ref ) = Cpanel::IPv6::Utils::load_range_config();

    $locale ||= Cpanel::Locale->get_handle();
    return ( $ret, $range_data_ref ) unless $ret;

    # Add CIDR style ranges to the data
    foreach my $name ( keys %{$range_data_ref} ) {

        my $range_ref = $range_data_ref->{$name};
        $range_ref->{'name'} = $name;

        my $first        = $range_ref->{'first'};
        my $last         = $range_ref->{'last'};
        my $range_string = "$first - $last";

        if ( !$range_ref->{'CIDR'} ) {
            my $ip_range = Cpanel::CPAN::Net::IP->new( $range_string, 6 );

            if ( $ip_range and $ip_range->prefixlen() ) {
                $range_ref->{'CIDR'} = $ip_range->short() . '/' . $ip_range->prefixlen();
            }
            else {
                $range_ref->{'CIDR'} = $locale->maketext('ERROR: Invalid Range');
            }
        }
    }

    my @ranges = values %{$range_data_ref};

    return ( $ret, \@ranges );
}

#
# Get the usage for an ipv6 range
#
sub ipv6_range_usage {
    my ($name) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my ( $ret, $existing_range_ref ) = Cpanel::IPv6::Utils::load_range_config();

    return ( 0, $locale->maketext('Invalid Range Name') ) unless exists $existing_range_ref->{$name};

    return ( 1, { 'used' => 20, 'free' => 1_000_000, 'forbidden' => 65536 } );
}

#
# Trim a range name string to it's max length
#
sub trim_range_name {
    my ($name) = @_;

    return _trim_field_to_max_length( $name, 64 );
}

#
# Trim a range note to
#
sub trim_range_note {
    my ($note) = @_;

    return _trim_field_to_max_length( $note, 256 );
}

#
# Take a string field, strip leading/trailing whitespace
# and, chop it down to max length if too long
#
sub _trim_field_to_max_length {
    my ( $string, $max_length ) = @_;

    # If string is blank/undef then nothing to do
    return unless $string;

    # Get rid of leading/trailing whitespace
    $string =~ s/^\s+|\s+$//g;

    # enforce max length
    $string = substr( $string, 0, $max_length ) if ( length($string) > $max_length );

    return $string;
}

1;
