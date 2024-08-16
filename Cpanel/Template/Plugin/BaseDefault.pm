package Cpanel::Template::Plugin::BaseDefault;

# cpanel - Cpanel/Template/Plugin/BaseDefault.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet safe here

use feature 'state';

use base 'Template::Plugin';

# MEMORY!
#  Do not load Cpanel () from this module as it
#  does not required it most of the time and it will
#  always already be loaded if it does
#
#  use Cpanel                            ();
#

use Cpanel::Encoder::Slugify      ();
use Cpanel::Encoder::Tiny         ();
use Cpanel::Encoder::URI          ();
use Cpanel::App                   ();
use Cpanel::Config::LoadCpConf    ();
use Cpanel::Server::Type          ();
use Cpanel::Debug                 ();
use Cpanel::Locale                ();
use Cpanel::MagicRevision         ();
use Cpanel::Analytics::UiIncludes ();    # better to build it in as its in the master template
use Cpanel::NVData();

use File::Spec         ();               ## for &template_exists
use Template::Filters  ();
use Template::VMethods ();
use Cpanel::Debug      ();
use Cpanel::LoadModule ();

=head1 MODULE

C<Cpanel::Template::Plugin::BaseDefault>

=head1 DESCRIPTION

C<Cpanel::Template::Plugin::BaseDefault> provides common helper methods to template toolkit.

This plugin should be used as a base plugin for other application specific plugins.

=head1 SYNOPSIS

Defining a application specific plugin that has the BaseDefaults helpers plus some special ones for the specific app.

  package Cpanel::Template::Plugin::AppSpecific;

  use cPstrict;

  # Inherit the common TT helper methods
  use parent 'Cpanel::Template::Plugin::BaseDefault';

  # Add your own custom TT helper methods for this specific app
  sub app_specific_action($plugin, $show) {
    ...
    return 1;
  }

  1;

And in your templates:

  USE NVData;
  USE AppSpecific;

  # Handle the oddities of NVData depending on storage in JSON or YAML.
  # NVData.get() for boolean will return either a /0 /1 from yaml or a JSON::PP::Boolean
  # from the JSON cache.
  SET showFavoritesDescriptions = to_boolean(NVData.get('showFavoritesDescriptions'));

  # Call the new AppSpecific helper.
  SET ok = app_specific_action(showFavoritesDescriptions);

=head1 VMETHODS

VMETHODS extend SCALAR, ARRAY and HASH types in Template Toolkit with new helper methods

=head2 uri()

Encode the string as a uri.

=head3 EXTENDS

SCALAR

=head2 url

Encode the string as a url.

=head3 EXTENDS

SCALAR

=head2 html

Encode the string as as html.

Use:

    SET value = '<a>123</a>';
    SET value_html = value.html();

Do NOT Use:

    SET value = '<a>123</a>';
    SET value_html = value FILTER html;

=head3 EXTENDS

SCALAR

=head2 index(match)

Perform a lookup of the index of a given string in the current string.

    SET value = 'abc';
    SET index_of_b = value.index('b');

=head3 EXTENDS

SCALAR

=head3 ARGUMENTS

=over

=item match - string

Substring to look for.

=back

=head2 slugify()

Used to encode text to be safe for id or css class name. Replaces special characters with safe characters.

=head3 EXTENDS

SCALAR

=head2 css()

Adds css filter.

Use this since syntax for SET x = y FILTER css doesn't work

=head3 EXTENDS

SCALAR

=head2 trim()

Trim the whitespace characters from the beginning and end of the string.

=head3 EXTENDS

SCALAR

=cut

my $locale;

sub load {
    my ( $class, $context ) = @_;

    my $stash = $context->stash();

    #This doesn't ship with TT currently, but it really should.
    if ( !defined $Template::VMethods::TEXT_VMETHODS->{'uri'} ) {
        $stash->define_vmethod(
            'scalar',
            'uri',
            \&Cpanel::Encoder::URI::uri_encode_str
        );
    }

    if ( !defined $Template::VMethods::TEXT_VMETHODS->{'url'} ) {
        $stash->define_vmethod(
            'scalar',
            'url',
            \&Template::Filters::url_filter
        );
    }

    # Adds html filter since syntax for SET x = y FILTER html doesn't work
    $stash->define_vmethod(
        'scalar',
        'html',
        \&Cpanel::Encoder::Tiny::safe_html_encode_str,
    );

    # Make fast text search
    $stash->define_vmethod(
        'scalar',
        'index',
        \&CORE::index,
    );

    # Used to encode text to be safe for id or css class name.
    $stash->define_vmethod(
        'scalar',
        'slugify',
        \&Cpanel::Encoder::Slugify::slugify,
    );

    # Adds css filter since syntax for SET x = y FILTER css doesn't work
    $stash->define_vmethod(
        'scalar',
        'css',
        \&Cpanel::Encoder::Tiny::css_encode_str,
    );

    if ( !defined $Template::VMethods::TEXT_VMETHODS->{'trim'} ) {
        $stash->define_vmethod(
            'scalar',
            'trim',
            $Template::Filters::FILTERS->{'trim'},
        );
    }

    @{$stash}{
        'MagicRevision',
        'cp_security_token',    ## consider using %ENV instead
        'locale',
        'ref',
        'deref',
        'to_boolean',
        'STASH',                #for debugging

        'cptext',
        'FORM',
        'CONF',                 ## consider using ExpVar instead
        'RAW_FORM',
        'template_exists',
        'calculate_magic_mtime',
        'calculate_magic_lex_mtime',
        'get_company_id',
        'user_feedback_text_for_more_locales',
        'cpanel_full_version',
        'cpanel_interface_analytics_allowed',
        'webmail_interface_analytics_allowed',
        'whm_interface_analytics_allowed',
      } = (
        \&Cpanel::MagicRevision::calculate_magic_url,
        $ENV{'cp_security_token'},
        ( ${^GLOBAL_PHASE} eq 'RUN' ? ( $locale ||= Cpanel::Locale::lh() ) : \&Cpanel::Locale::lh ),
        \&_ref,
        \&_deref,
        \&_to_boolean,
        sub { return $context->stash() },    #for debugging

        \&cptext,
        \%Cpanel::FORM,                      # PPI NO PARSE - only used if loaded - TODO: Make this the same as CPANEL.FORM below.
        \&_get_cpconf,
        \&_get_raw_form,
        sub { return template_exists( $context, @_ ) },
        \&Cpanel::MagicRevision::get_magic_revision_mtime,
        \&Cpanel::MagicRevision::get_magic_revision_lex_mtime,
        \&_get_company_id,
        \&_user_feedback_text_for_more_locales,
        \&_cpanel_full_version,
        sub { return _interface_analytics_allowed('cpanel') },
        sub { return _interface_analytics_allowed('webmail') },
        sub { return _interface_analytics_allowed('whm') }
      );

    @{ $stash->{'CPANEL'} }{
        'cookies',
        'ua_is_ie',
        'is_cpanel',
        'is_dnsonly',
        'get_producttype',
        'is_webmail',
        'is_whm',
        'appname',
        'now',
        'get_cjt_url',
        'get_cjt_lex_url',
        'get_cjt_lex_script_tag',
        'get_js_lex_url',
        'get_js_lex_script_tag',
        'get_js_localized_url',
        'get_js_lex_app_rel_path',
        'get_js_lex_app_full_path',
        'CPCONF',
        'authuser',
        'FORM',    #ixhash modified!
        'get_raw_form',
        'read_uploaded_file',
        'get_js_url',
        'is_sandbox',
        'is_debug_mode_enabled',
        'is_qa_mode_enabled',
        'analytics_ui_includes_are_enabled',
        'version',
        'has_modenv',
        'major_version',
        'nonce'
      }
      = (
        \&_get_cookies,
        \&_ua_is_ie,
        \&Cpanel::App::is_cpanel,
        \&Cpanel::Server::Type::is_dnsonly,
        \&Cpanel::Server::Type::get_producttype,
        \&Cpanel::App::is_webmail,
        \&Cpanel::App::is_whm,
        $Cpanel::appname || $Cpanel::App::appname,
        \&_now,
        sub { require Cpanel::JS; Cpanel::JS::get_cjt_url(@_) },
        sub { require Cpanel::JS; Cpanel::JS::get_cjt_lex_url( $context->stash()->{'locale'} ) },
        sub { require Cpanel::JS; Cpanel::JS::get_cjt_lex_script_tag( $context->stash()->{'locale'} ) },
        sub { require Cpanel::JS; Cpanel::JS::get_js_lex_url( $context->stash()->{'locale'}, $_[0] ) },
        sub { require Cpanel::JS; Cpanel::JS::get_js_lex_script_tag( $context->stash()->{'locale'}, $_[0] ) },
        sub { require Cpanel::JS; Cpanel::JS::get_js_localized_url( $context->stash()->{'locale'}, $_[0] ) },
        sub { require Cpanel::JS; Cpanel::JS::get_js_lex_app_rel_path( $context->stash()->{'locale'}, $_[0], $_[1] ) },
        sub { require Cpanel::JS; Cpanel::JS::get_js_lex_app_full_path( $context->stash()->{'locale'}, $_[0], $_[1] ) },
        \&_get_cpconf,
        $Cpanel::authuser || $ENV{'REMOTE_USER'},
        $Cpanel::Form::Parsed_Form_hr,    # PPI NO PARSE - only used if loaded - TODO: Make this the same as FORM above.
        \&_get_raw_form,
        \&_read_uploaded_file,
        \&_get_js_url,
        \&is_sandbox,
        \&_is_debug_mode_enabled,
        \&_is_qa_mode_enabled,
        \&_analytics_ui_includes_are_enabled,
        sub { require Cpanel::GlobalCache; return Cpanel::GlobalCache::data( 'cpanel', 'version_display' ) },
        sub { require Cpanel::GlobalCache; return Cpanel::GlobalCache::data( 'cpanel', 'has_modenv' ) },
        sub { require Cpanel::Version;     return Cpanel::Version::get_short_release_number(); },
        sub { require Cpanel::CSP::Nonces; state $counter = 0; return Cpanel::CSP::Nonces->instance->nonce( $counter++ ) },
      );

    my $varcache = $context->{CONFIG}{NAMESPACE}{varcache};
    if ($varcache) {

        # Adding this setting to varcache so the config load doesn't happen everytime.
        $varcache->set( 'is_package_update_enabled', _is_package_update_enabled() );
    }
    return $class;
}

sub _get_js_url {
    my ($relative_url) = @_;

    chop($relative_url) while substr( $relative_url, 1 ) eq '/';

    my $docroot = Cpanel::MagicRevision::get_docroot();

    my $url = "$docroot/$relative_url";

    return Cpanel::MagicRevision::calculate_magic_url( substr( $url, length $docroot ) );
}

sub is_sandbox {
    return -e '/var/cpanel/dev_sandbox' ? 1 : 0;
}

sub _get_cookies {
    require Cpanel::Cookies;

    #Copy the hash so that template authors can’t corrupt internals.
    return { %{ Cpanel::Cookies::get_cookie_hashref() } };
}

my $cpconf;

sub _get_cpconf {
    return ( $cpconf ||= scalar Cpanel::Config::LoadCpConf::loadcpconf_not_copy() );
}

=head1 FUNCTIONS

=head2 ref(VALUE)

Get the reference type of a value.

=head3 ARGUMENTS

Anything including undef.

=head3 RETURNS

The reference type as defined by perl ref() method.

=cut

sub _ref {
    return CORE::ref shift();
}

=head2 deref(VALUE)

Dereference a value. Only works for SCALAR, ARRAY, HASH references.

It will pass thru the value if its not a reference or not one of
the allowed types.

=head3 ARGUMENTS

Anything including undef.

=head3 RETURNS

The value if its not a ref, the derefereced value if
its a ref of one of the allowed types or undef.

=cut

sub _deref {
    my $value    = shift;
    my $ref_type = CORE::ref $value;
    if ( !$ref_type ) {
        return $value;
    }
    elsif ( $ref_type eq 'SCALAR' ) {
        return $$value;
    }
    elsif ( $ref_type eq 'ARRAY' ) {
        return @$value;
    }
    elsif ( $ref_type eq 'HASH' ) {
        return %$value;
    }
    else {
        return $value;
    }
}

=head2 to_boolean(VALUE)

Convert scalar \0 \1 to something tt can use but pass thru other values.

=head3 ARGUMENTS

Any value including undef.

=head3 RETURNS

The value so that it will be a empty, true or false in a way that TT can interpret it.

=cut

sub _to_boolean {
    my $value    = shift;
    my $ref_type = CORE::ref $value;
    if ( $ref_type eq 'SCALAR' ) {
        return _deref($value);
    }
    else {
        return $value;
    }
}

#NOTE: used in testing
sub _now {
    return time;
}

sub _get_raw_form {
    local $Cpanel::IxHash::Modify = 'none';
    require Cpanel::Form;
    my $key = shift;
    if ($key) {
        return $Cpanel::Form::Parsed_Form_hr->{$key};
    }
    else {
        my %pure_form = %{$Cpanel::Form::Parsed_Form_hr};
        return \%pure_form;
    }
}

sub _read_uploaded_file {
    my $formname = shift;
    require Cpanel::Form;
    my $fh = Cpanel::Form::open_uploaded_file($formname);
    return if !$fh;

    local $/;
    my $slurped = <$fh>;
    return $slurped;
}

sub cptext {

    # The <cptext> cpanel tag was intended to make it easier to do maketext in cpanel tag syntax. Outside of that, i.e. in TT, it gains us nothing and puts it that much farther from the object (and makes our TT that much bigger) ## no extract maketext
    Cpanel::Debug::log_deprecated('cptext() in Template Toolkit is deprecated as of 11.46 (its eventual removal is being tracked via PBI 27397). Use locale.maketext() instead.');    ## no extract maketext

    return $locale->makevar(@_);
}

=head2 template_exists($path)

Check the the template toolkit template exists at the given path. Use this with optionally installed templated from Plugins or other optional distribution system.

=head3 ARGUMENTS

=over

=item $path - string

The full path to the template.

=back

=head3 RETURNS

true value when the template exists, false value otherwise.

=head3 SEE ALSO

branding/
stdheader.tt
stdfooter.tt

=cut

sub template_exists {
    my ( $context, $name ) = @_;

    my $providers = $context->{LOAD_TEMPLATES};

    for my $provider (@$providers) {
        ## stolen from &Template::Provider::fetch
        my @names;
        if ( File::Spec->file_name_is_absolute($name)
            || ( $name =~ m/$Template::Provider::RELATIVE_PATH/o ) ) {
            push( @names, $name );
        }
        else {
            ## stolen from &Template::Provider::_fetch_path
            my $paths = $provider->paths();
            foreach my $dir (@$paths) {
                my $path = File::Spec->catfile( $dir, $name );
                push( @names, $path );
            }

            # also include DEFAULT, after INCLUDE_PATH
            push( @names, $provider->{DEFAULT} )
              if defined $provider->{DEFAULT}
              && $name ne $provider->{DEFAULT};
        }

        ## stolen from &Template::Provider::_load
        for my $name (@names) {
            if ( $provider->_template_modified($name) ) {    # does template exist?
                return 1;
            }
        }
    }
    return;
}

sub clearcache {
    $locale = undef;
    return;
}

sub _ua_is_ie {
    my $ua    = $ENV{'HTTP_USER_AGENT'} || return;
    my @match = ( $ua =~ m{MSIE\s+([\d.]*)} );
    if ( scalar @match ) {
        return $match[0] ? 0 + $match[0] : 1;
    }

    return;
}

sub _is_debug_mode_enabled {
    my $form = $Cpanel::Form::Parsed_Form_hr || {};    # PPI NO PARSE - only used if loaded
    return ( $form->{'debug'} || $Cpanel::CPVAR{'debug'} || _get_cpconf()->{'debugui'} ) ? 1 : 0;
}

sub _is_qa_mode_enabled {
    return -e '/var/cpanel/enable_qa_mode' ? 1 : 0;
}

*_analytics_ui_includes_are_enabled = *Cpanel::Analytics::UiIncludes::are_enabled;

sub _get_company_id {
    require Cpanel::License::CompanyID;
    my $companyid;
    eval { $companyid = Cpanel::License::CompanyID::get_company_id() };
    return $companyid;
}

sub _user_feedback_text_for_more_locales {
    return Cpanel::Locale::user_feedback_text_for_more_locales();
}

sub _cpanel_full_version {
    require Cpanel::Version;
    return Cpanel::Version::get_version_full();
}

sub _interface_analytics_allowed {
    my $interface = shift;
    my $setting   = Cpanel::NVData::_get( 'analytics', undef, 0, $interface );
    return ( $setting eq "on" ) ? 1 : 0;

    # return $setting;
}

sub _is_package_update_enabled {
    Cpanel::LoadModule::load_perl_module('Cpanel::Update::Config');
    my $update_conf_ref = Cpanel::Update::Config::load();
    return ( $update_conf_ref->{'RPMUP'} ne 'never' && $update_conf_ref->{'UPDATES'} ne 'never' );
}

=head2 is_feature_enabled($flag_name)

Checks if an feature flag is enabled on the system.

=head3 ARGUMENTS

=over

=item $flag_name - string

The name of the feature flag to check.

=back

=head3 RETURNS

true value when the feature is enabled, fasle otherwise.

=cut

sub is_feature_enabled {
    my ( $self, $feature_flag ) = @_;
    require Cpanel::FeatureFlags::Cache;
    return Cpanel::FeatureFlags::Cache::is_feature_enabled($feature_flag);
}

1;
