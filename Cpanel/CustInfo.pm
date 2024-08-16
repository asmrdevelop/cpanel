package Cpanel::CustInfo;

# cpanel - Cpanel/CustInfo.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel             ();
use Cpanel::App        ();
use Cpanel::LoadModule ();
use Cpanel::Locale     ();

# Developer Notes:
#
# This module implements the main public entry points for the customer
# information including contact information and notification preferences.
# It consists of api1 and api2 calls. Many internal modules also use
# Cpanel::CustInfo::Save as a semi-private entry point to the save
# functionality.
#
# Shipped:
#
# Cpanel::CustInfo    - no
# Cpanel::CustInfo::* - yes
#
# Child Modules in the Namespace:
#
# Cpanel::CustInfo::Save  - contains routines related to saving customer
# information. Many other modules and tests in the product make use of
# these routines directly thus this modules interface was preserved.
#
# Cpanel::CustInfo::Impl - this module implements the core operations for
# the public interfaces in Cpanel::CustInfo and semi-private interfaces in
# Cpanel::CustInfo::Save.  The module have very limited dependence on
# global variables unlike the original implementation it replaces.
#
# Cpanel::CustInfo::Validate - contains various validation routines that
# are specific to this application. Other validator in the Cpanel::Validate
# namespace are also used.
#
# Cpanel::CustInfo::Model - contains data module generation methods for
# the Customer Information properties available in the system and for the
# requested user.
#
# Cpanel::CustInfo::Util - contains utility methods for various aspects
# of the implementation.

# Save the contact information for the user. Defaults to the current user.
#
# API:
#   API2
#
# Arguments
#   username - string - optional virtual user. Saves the customer information for this user.
#                       If missing, will default to the currently authenticated user.
#                       NOTE: this was added here to keep from breaking the existing api2
#                       interface. It is not persisted to the customer information data store.
#   *        - properties to save'
#
# Returns
#
#   arrayref of hashes - where each has has the following structure:
#
#       name - string - the key from %CONTACT_FIELDS,
#       descp - string - the (localized) description of this field
#       value - string|number - the saved value. For boolean fields, it will be 1 or 0. Otherwise its a string.
#       display_value - string - same as value, but whitespace-trimmed. Will be 'on' or 'off' for boolean fields.
#
sub api2_savecontactinfo {
    my (%args) = @_;

    my $username = delete $args{username};
    $username ||= $Cpanel::authuser;

    my $status = Cpanel::CustInfo::_validate_username( $username, $Cpanel::authuser );
    unless ($status) {
        $Cpanel::CPERROR{custinfo} = "‘$Cpanel::authuser’ does not have access to save contact info for ‘$username’.";
        return;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::CustInfo::Impl');
    return Cpanel::CustInfo::Impl::save(
        appname   => $Cpanel::appname,
        cpuser    => $Cpanel::user,
        cphomedir => $Cpanel::homedir,
        username  => $username,
        data      => \%args,
    );
}

#
# Fetch all the customer info properties that are usable.
#
# API:
#   API2
#
# Arguments:
#   username - string - optional virtual user. Will lookup the customer info for this user .
#                       If missing, will default to the currently authenticated user.
# Returns:
#    Arrayref of hashes with the following properties
#       type           - string  - type of the property: string or boolean only
#       value          - string|boolean - raw value of the property
#       enabled        - boolean - if the value truthy, this property is 1, otherwise its 0. Only
#                                  meaningful for boolean properties.
#       name           - string - name of this property.
#       descp          - string - description for the property
#       onchangeparent - string - optional, if present, it points to another boolean notice
#                                 property. Only present on boolean properties.
#
sub api2_displaycontactinfo {
    my (%args) = @_;

    my $username = delete $args{username};
    $username ||= $Cpanel::authuser;

    my $status = Cpanel::CustInfo::_validate_username( $username, $Cpanel::authuser );
    unless ($status) {
        $Cpanel::CPERROR{custinfo} = "‘$Cpanel::authuser’ does not have access to the contact info for ‘$username’.";
        return;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::CustInfo::Impl');
    return Cpanel::CustInfo::Impl::fetch_display(
        appname   => $Cpanel::appname,
        cpuser    => $Cpanel::user,
        cphomedir => $Cpanel::homedir,
        username  => $username,
    );
}

#
# Fetch all the address related customer information properties. Includes:
#    * contact email addresses
#    * push bullet access token
#
# API:
#   API2
#
# Arguments:
#   username   - string  - optional virtual user. Will lookup the customer information for this user.
#                          if missing, will default to the currently authenticated user.
#   no_default - boolean - optional, if truthy, will suppress looking up the email via the legacy
#                          contact email system.
# Returns:
#    Arrayref of hashes with the following properties
#       type           - string  - type of the property: string
#       value          - string| - raw value of the property
#       enabled        - boolean - always 1
#       name           - string - name of this property.
#       descp          - string - description for the property
#
sub api2_get_contact_address {
    my (%args) = @_;

    $args{username} ||= $Cpanel::authuser;

    Cpanel::LoadModule::load_perl_module('Cpanel::CustInfo::Impl');
    return Cpanel::CustInfo::Impl::fetch_addresses(
        appname    => $Cpanel::appname,
        cpuser     => $Cpanel::user,
        cphomedir  => $Cpanel::homedir,
        username   => $args{username},
        no_default => $args{no_default},
    );
}

#
# Fetch all the usable boolean customer information properties. These are used
# primarily to enable/disable the sending of notices.
#
# API:
#   API2
#
# Arguments:
#   username - string - optional virtual user. Will lookup the customer information for this user.
#                       If missing, this will default to the currently authenticated user.
# Returns:
#    Arrayref of hashes with the following properties
#       type           - string  - type of the property: string or boolean only
#       value          - string|boolean - raw value of the property
#       enabled        - boolean - if the value truthy, this property is 1, otherwise its 0. Only
#                                  meaningful for boolean properties.
#       name           - string - name of this property.
#       descp          - string - description for the property
#       onchangeparent - string - optional, if present, it points to another boolean notice
#                                 property. Only present on boolean properties.
sub api2_get_contact_preferences {
    my (%args) = @_;
    $args{username} ||= $Cpanel::authuser;

    my $status = Cpanel::CustInfo::_validate_username( $args{username}, $Cpanel::authuser );
    unless ($status) {
        $Cpanel::CPERROR{custinfo} = "‘$Cpanel::authuser’ does not have access to the contact info for ‘$args{username}’.";
        return;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::CustInfo::Impl');
    return Cpanel::CustInfo::Impl::fetch_preferences(
        appname   => $Cpanel::appname,
        cpuser    => $Cpanel::user,
        cphomedir => $Cpanel::homedir,
        username  => $args{username},
    );
}

#
# Checks if you have a contact email address. If not, it prints a notification to the user.
# Do not use this in new code.
#
# API:
#   API1
#
# Arguments:
#   n/a
#
# Returns:
#   n/a
#
sub checkcontactemail {
    my $contactemail = getemail(1);
    if ( !$contactemail ) {
        print Cpanel::Locale->get_handle()->maketext('You have not set a contact email address.');
        print Cpanel::Locale->get_handle()->maketext('You will be unable to receive notifications or reset your password if you do not set a contact email address.');
    }
    return '';
}

#
# Fetches the contact email address for a user. Do not use this in new code.
#
# API:
#   API1
#
# Arguments:
#   boolean - if truthy returns output, otherwise prints output directly to STDOUT.
#   string  - optional user to fetch. May be either the current cpanel user or a webmail/virtual
#             user belonging to that cpanel user. If not provided, it will default to the currently
#             authenticated user.
#
# Returns:
#   string - the contact email for the user.
#
sub getemail {
    my ( $return_semantics, $username ) = @_;

    $return_semantics ||= 0;
    $username         ||= $Cpanel::authuser;

    # Cpanel::AppSafe should have prevented us from getting here,
    # but just in case:
    die "Forbidden in webmail!" if Cpanel::App::is_webmail();

    my $email = ( \%Cpanel::CPDATA )->contact_emails_ar()->[0];

    if ($email) {
        if ( !$return_semantics ) {
            print $email;
        }
        else {
            return $email;
        }
    }

    return '';
}

sub _validate_username {
    my ( $desired_username, $authed_username ) = @_;

    # If this is a webmail user, then they only have
    # access to make changes for their user
    if ( $Cpanel::appname eq 'webmail' ) {
        return $desired_username eq $authed_username ? 1 : 0;
    }

    return 1;
}

#
# Standard api2 map. Returns the configuration data for the requested
# api2 method implement in this module.
#
# Arguments:
#   string - function name.
#
# Returns:
#   hash - API2 call setup hash for the requested api method.
#
my $allow_demo = { allow_demo => 1 };

our %API = (
    'displaycontactinfo' => $allow_demo,
    'savecontactinfo'    => $allow_demo,
    'contactemails'      => {
        'func'     => 'api2_get_contact_address',
        'csssafe'  => 1,
        allow_demo => 1,
    },
    'contactprefs' => {
        'func'     => 'api2_get_contact_preferences',
        'csssafe'  => 1,
        allow_demo => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
