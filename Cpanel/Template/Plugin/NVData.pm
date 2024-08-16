package Cpanel::Template::Plugin::NVData;

# cpanel - Cpanel/Template/Plugin/NVData.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';

use Cpanel::App        ();
use Cpanel::LoadModule ();
use Cpanel::Debug      ();

use Cpanel::Imports;

=head1 NAME

Cpanel::Template::Plugin::NVData

=head1 DESCRIPTION

Plugin that exposes various NVData related method to the Template Toolkit pages.

=cut

sub _get_whm {
    my ( $name, $stor, $use_pattern_matching ) = @_;

    if ( !$INC{'Whostmgr/NVData.pm'} ) {
        Cpanel::LoadModule::load_perl_module('Whostmgr::NVData');
    }

    unless ($use_pattern_matching) {
        return Whostmgr::NVData::get( $name, length $stor ? $stor : () );
    }

    my $nv = Whostmgr::NVData::get_ref($stor);
    return { map { index( $_, $name ) == 0 ? ( $_ => $nv->{$_} ) : () } keys %$nv };
}

sub _get_cpanel {
    my ( $name, $stor, $use_pattern_matching ) = @_;

    die locale()->maketext("The [asis,cPanel] and [asis,Webmail] interfaces do not support alternative datastores.") if $stor;
    die locale()->maketext("The [asis,cPanel] and [asis,Webmail] interfaces do not support partial matches.")        if $use_pattern_matching;

    if ( !$INC{'Cpanel/API/NVData.pm'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::API::NVData');
    }

    my $result = Cpanel::API::NVData::_get($name);
    if ($result) {
        return $result->[0]{value};
    }
    return;
}

=head1 METHODS

=head2 C<get(SELF, NAME, STOR, USE_PATTERN_MATCHING, APPLICATION)>

Retrieve NVData items.

B<Note:>

For consistency between cPanel and WHM, this method only fetches
one value unless partial match is requested. Partial matches
are only supported in WHM at this time.

=head3 Arguments

Arguments are positional.

=over

=item SELF - reference to the plugin

=item NAME - string

name of the variable to retries from NVData. May be a pipe delimited list, but only the first item in the list is used.

=item STOR - string - optional

file backing store for the NVData.

=item USE_PATTERN_MATCHING - boolean - optional

when enabled (in WHOSTMGR only) the call treats the key as a pattern for the first part of the NVData property name.

=item APPLICATION - string - optional

The application name: webmail, cpanel, whostmrg. If not provided it uses C<$Cpanel::App:appname>.

=back

=head3 Returns

Array Ref - with one element for CPANEL, WEBMAIL & WHOSTMGR

If the property exists in the store, the element is a hash ref with the following properties:

=over

=item name - String

Name of the property.

=item value - Any

Value of the property. Usually a string.

or

Hash Ref  - for WHOSTMGR only and with pattern matching enabled with one or more property/value pairs based on the number of matches

=back

=head3 Examples

Say that C<abc.store> contains the following properties in its internal database:

    prefix:x => '100'
    prefix:y => '200'
    prefix:z => '300'

=head4 Example for WHOSTMGR with USE_PATTERN_MATCHING enabled (TT):

So in template toolkit you call:

    SET ret = NVDATA.get("prefix:", "abc.stor", 1 );

Then ret will look like this:

    {
        'prefix:x' => '100',
        'prefix:y' => '200',
        'prefix:z' => '300'
    }

=head4 Example for USE_PATTERN_MATCHING undefined or disabled (TT):

So in template toolkit if you call:

    SET ret = NVDATA.get("prefix:x");

Then ret will look like this:

    [ '100' ]

And if you call:

    SET ret = NVDATA.get("unknown");

Then ret will look like this:

    [ undef ]

=cut

sub get {
    my ( undef, $name, $stor, $use_pattern_matching, $app ) = @_;
    $name =~ s{\|.*}{} if length $name;

    return if !length $name;

    $app ||= $Cpanel::App::appname;
    if ( $app && ( $app =~ m{wh}i ) ) {
        return _get_whm( $name, $stor, $use_pattern_matching );
    }
    else {
        return _get_cpanel( $name, $stor, $use_pattern_matching );
    }
}

=head2 C<get_page_nvdata()>

Retrieve the NVData collection stored for the page. The key name is automatically derived from the SCRIPT_NAME environment variable.

B<Note>

Usually this property is persisted as a JSON compatible string that represents a Hash so the most common return type is a hash ref.

=head3 Arguments

N/A

=head3 Returns

Anything stored in the property.

=cut

sub get_page_nvdata {
    my $page_nvdata_key = $ENV{'SCRIPT_NAME'};
    return if !defined $page_nvdata_key;

    $page_nvdata_key =~ s{\A\Q$ENV{'cp_security_token'}\E}{};
    $page_nvdata_key =~ tr{/}{_};
    $page_nvdata_key =~ s{\.tt$}{};

    return if !$page_nvdata_key;

    my $json = __PACKAGE__->get($page_nvdata_key);

    return if !$json;

    Cpanel::LoadModule::load_perl_module('Cpanel::JSON');
    my $ret = eval { Cpanel::JSON::Load($json); };

    return $ret if $ret;

    # We got here if the NVData was invalid, so warn.
    Cpanel::Debug::log_warn("Invalid JSON string in nvdata $page_nvdata_key: $json");
    return;
}

1;
