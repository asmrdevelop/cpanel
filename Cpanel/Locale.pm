package Cpanel::Locale;

# cpanel - Cpanel/Locale.pm                           Copyright 2022 cPanel L.L.C
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::Locale

=head1 DESCRIPTION

This module contains the implementation for C<Cpanel::Locale>.

The methods that start with api2_ are specifically for api2 calls.
Be careful to only make backwardly compatible changes in these methods.
For other methods there may be more freedom to make changes as they
are private to this module or used to implement the UAPI calls.

One of the main features of this module is that it caches the current
users current locale in a singleton cache. Use the C<Cpanel::Locale::lh()>
method to fetch this singleton.

This module contains both package and instance methods. Pay attention
to the use case for each method.

=cut

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

BEGIN {

    # 'IGNORE_WIN32_LOCALE'  being true causes I18N::LangTags::Detect (used by Cpanel::CPAN::Locale::Maketext)
    #  to not try and load Win32::Locale when it is doing locale name operations
    $ENV{'IGNORE_WIN32_LOCALE'} = 1;
}

use parent qw{ Cpanel::CPAN::Locale::Maketext::Utils };

use Cpanel::Locale::Utils          ();    # Individual Locale modules depend on this being brought in here, if it is removed they will all need updated. Same for cpanel.pl
use Cpanel::Locale::Utils::Paths   ();
use Cpanel::CPAN::Locale::Maketext ();
use Cpanel::Exception              ();

use constant _ENOENT => 2;

BEGIN {
    local $^H = 0;    # cheap no warnings without importing it
    local $^W = 0;

    # this is only used to remove the '_AUTO' keys which is happening
    # at init for most binaries and this is useless
    # Note: we could also have removed it from Cpanel/CPAN/Locale/Maketext/Utils.pm
    #       but this could be lost on updates
    *Cpanel::CPAN::Locale::Maketext::Utils::remove_key_from_lexicons = sub { };    # PPI NO PARSE - loaded above - disabled
}

our $SERVER_LOCALE_FILE = '/var/cpanel/server_locale';

# New locales should be added to this list
# by using the following to build the list
# ls /var/cpanel/locale |grep '.cdb$' | perl -pi -e 's/\.cdb$/ => 1,/g'
#
#  Then change 1 or the value from Cpanel::CPAN::Locales::DB::CharacterOrientation::Tiny
#
# If a new locale is not added it will still work
# however it will be much slower and use more memory
#
#
our $LTR = 1;
our $RTL = 2;
#
our %known_locales_character_orientation = (
    ar               => $RTL,
    bn               => $LTR,
    bg               => $LTR,
    cs               => $LTR,
    da               => $LTR,
    de               => $LTR,
    el               => $LTR,
    en               => $LTR,
    en_US            => $LTR,
    en_GB            => $LTR,
    es_419           => $LTR,
    es               => $LTR,
    es_es            => $LTR,
    fi               => $LTR,
    fil              => $LTR,
    fr               => $LTR,
    he               => $RTL,
    hi               => $LTR,
    hu               => $LTR,
    i_cpanel_snowmen => $LTR,
    i_cp_qa          => $LTR,
    id               => $LTR,
    it               => $LTR,
    ja               => $LTR,
    ko               => $LTR,
    ms               => $LTR,
    nb               => $LTR,
    nl               => $LTR,
    no               => $LTR,
    pl               => $LTR,
    pt_br            => $LTR,
    pt               => $LTR,
    ro               => $LTR,
    ru               => $LTR,
    sl               => $LTR,
    sv               => $LTR,
    th               => $LTR,
    tr               => $LTR,
    uk               => $LTR,
    vi               => $LTR,
    zh               => $LTR,
    zh_tw            => $LTR,
    zh_cn            => $LTR,
);

=head1 FUNCTIONS

=cut

# logger façade:
#   1. We don’t use Cpanel::Imports to avoid recursive dependency.
#   2. This has to be internal so that it can’t be called via bracket notation.
my $logger;

sub _logger {
    require Cpanel::Logger;
    return ( $logger ||= Cpanel::Logger->new() );
}

#legacy misspelling
*get_lookup_hash_of_mutli_epoch_datetime = *get_lookup_hash_of_multi_epoch_datetime;

sub preinit {
    if ( exists $INC{'Cpanel.pm'} && !$Cpanel::CPDATA{'LOCALE'} ) {
        require Cpanel::Locale::Utils::User if !exists $INC{'Cpanel/Locale/Utils/User.pm'};
        Cpanel::Locale::Utils::User::init_cpdata_keys();
    }

    if ( $ENV{'HTTP_COOKIE'} ) {
        require Cpanel::Cookies unless $INC{'Cpanel/Cookies.pm'};

        # build %Cpanel::Cookies (if it has not already been built elsewhere) from HTTP_COOKIES
        if ( !keys %Cpanel::Cookies ) {
            %Cpanel::Cookies = %{ Cpanel::Cookies::get_cookie_hashref() };
        }
    }

    %Cpanel::Grapheme = %{ Cpanel::Locale->get_grapheme_helper_hashref() };
    return 1;
}

################################################
#### MakeText methods that need sub-classed ####
################################################

sub makevar {
    return $_[0]->maketext( ref $_[1] ? @{ $_[1] } : @_[ 1 .. $#_ ] );    ## no extract maketext
}

*maketext = *Cpanel::CPAN::Locale::Maketext::maketext;                    ## no extract maketext

#### we do this here so we can lookup the user's locale if none is given ####
my %singleton_stash = ();

# Confirm all tied hashes for locale are cleared before handing off to B::C

BEGIN {
    no warnings;    ## no critic(ProhibitNoWarnings)
    CHECK {
        if ( ( $INC{'O.pm'} || $INC{'Cpanel/BinCheck.pm'} || $INC{'Cpanel/BinCheck/Lite.pm'} ) && %singleton_stash ) {
            die("If you use a locale at begin time, you are responsible for deleting it too. Try calling _reset_singleton_stash\n");
        }
    }
}

#### Should only be used for testing or when we need to reset the module to a clean state
#### usually when we are loading data on one physical machine and then running the code on another
sub _reset_singleton_stash {
    foreach my $class ( keys %singleton_stash ) {
        foreach my $args_sig ( keys %{ $singleton_stash{$class} } ) {
            $singleton_stash{$class}{$args_sig}->cpanel_detach_lexicon();
        }
    }
    %singleton_stash = ();
    return 1;
}

sub get_handle {
    preinit();
    no warnings 'redefine';
    *get_handle = *_real_get_handle;
    goto &_real_get_handle;
}

sub _map_any_old_style_to_new_style {
    my (@locales) = @_;
    if ( grep { !$known_locales_character_orientation{$_} && index( $_, 'i_' ) != 0 } @locales ) {
        require Cpanel::Locale::Utils::Legacy;
        goto \&Cpanel::Locale::Utils::Legacy::map_any_old_style_to_new_style;
    }
    return @locales;
}

our $IN_REAL_GET_HANDLE = 0;

sub _setup_for_real_get_handle {    ## no critic qw(RequireArgUnpacking)

    if ($IN_REAL_GET_HANDLE) {
        _load_carp();
        if ( $IN_REAL_GET_HANDLE > 1 ) {
            die 'Cpanel::Carp'->can('safe_longmess')->("Attempted to call _setup_for_real_get_handle from _setup_for_real_get_handle");
        }
        warn 'Cpanel::Carp'->can('safe_longmess')->("Attempted to call _setup_for_real_get_handle from _setup_for_real_get_handle");
        if ($Cpanel::Exception::IN_EXCEPTION_CREATION) {    # PPI NO PARSE - Only care about this check if the module is loaded
            $Cpanel::Exception::LOCALIZE_STRINGS = 0;       # PPI NO PARSE - Only care about this check if the module is loaded
        }
    }
    local $IN_REAL_GET_HANDLE = $IN_REAL_GET_HANDLE + 1;

    # CPANEL-10445: Required since we've banned use of Cpanel module in whostmgr binaries.
    if ( defined $Cpanel::App::appname && defined $ENV{'REMOTE_USER'} ) {    # PPI NO PARSE - Only care about this check if the module is loaded
        if (
            $Cpanel::App::appname eq 'whostmgr'                              # PPI NO PARSE - Only care about this check if the module is loaded
            && $ENV{'REMOTE_USER'} ne 'root'
        ) {

            require Cpanel::Config::HasCpUserFile;
            if ( Cpanel::Config::HasCpUserFile::has_readable_cpuser_file( $ENV{'REMOTE_USER'} ) ) {
                require Cpanel::Config::LoadCpUserFile::CurrentUser;
                my $cpdata_ref = Cpanel::Config::LoadCpUserFile::CurrentUser::load( $ENV{'REMOTE_USER'} );

                # Only assign if cpuser file isn't empty.
                if ( scalar keys %{$cpdata_ref} ) {
                    *Cpanel::CPDATA = $cpdata_ref;
                }
            }
        }
    }

    my ( $class, @langtags ) = (
        $_[0],
        (
              defined $_[1]                                                                   ? _map_any_old_style_to_new_style( (@_)[ 1 .. $#_ ] )
            : exists $Cpanel::Cookies{'session_locale'} && $Cpanel::Cookies{'session_locale'} ? _map_any_old_style_to_new_style( $Cpanel::Cookies{'session_locale'} )
            : ( exists $Cpanel::CPDATA{'LOCALE'} && $Cpanel::CPDATA{'LOCALE'} )               ? ( $Cpanel::CPDATA{'LOCALE'} )
            : ( exists $Cpanel::CPDATA{'LANG'} && $Cpanel::CPDATA{'LANG'} )                   ? ( _map_any_old_style_to_new_style( $Cpanel::CPDATA{'LANG'} ) )
            :                                                                                   ( get_server_locale() )
        )
    );

    # always make sure en is available.  It may need to be re-inited after a reset
    if ( !$Cpanel::Locale::CDB_File_Path ) {
        $Cpanel::Locale::CDB_File_Path = Cpanel::Locale::Utils::init_lexicon( 'en', \%Cpanel::Locale::Lexicon, \$Cpanel::Locale::VERSION, \$Cpanel::Locale::Encoding );
    }

    _make_alias_if_needed( @langtags ? @langtags : 'en_us' );

    return @langtags;
}

my %_made_aliases;

sub _make_alias_if_needed {
    foreach my $tag ( grep { ( $_ eq 'en' || $_ eq 'i_default' || $_ eq 'en_us' ) && !$_made_aliases{$_} } ( 'en', @_ ) ) {

        # this make_alias() should only be necessary here because if the given args are not
        # found then Locale::Maketext automatically falls back to looking for
        # the superordinate (e.g. if 'fr_ca' was specified and does not exist, it will try 'fr')
        Cpanel::Locale->make_alias( [$tag], 1 );
        $_made_aliases{$tag} = 1;
    }
    return 0;
}

sub _real_get_handle {
    my ( $class, @arg_langtags ) = @_;

    my @langtags = _setup_for_real_get_handle( $class, @arg_langtags );
    @langtags = map { my $l = $_; $l = 'en' if ( $l eq 'en_us' || $l eq 'i_default' ); $l } grep { $class->cpanel_is_valid_locale($_) } @langtags;
    @langtags = ('en') unless scalar @langtags;

    # order is important so we don't sort() in an attempt to normalize (i.e. fr, es is not the same as es, fr)
    my $args_sig = join( ',', @langtags ) || 'no_args';

    return (
        ( defined $singleton_stash{$class}{$args_sig} && ++$singleton_stash{$class}{$args_sig}->{'_singleton_reused'} )
        ? $singleton_stash{$class}{$args_sig}
        : ( $singleton_stash{$class}{$args_sig} = Cpanel::CPAN::Locale::Maketext::get_handle( $class, @langtags ) )
    );

    # do as direct function instead of SUPER method to avoid traversing ISA
}

sub get_non_singleton_handle {
    my ( $class, @arg_langtags ) = @_;

    my @langtags = _setup_for_real_get_handle( $class, @arg_langtags );

    return Cpanel::CPAN::Locale::Maketext::get_handle( $class, @langtags );
}

# object specific initialization
sub init {
    my ($lh) = @_;

    $lh->SUPER::init();

    $lh->_initialize_unknown_phrase_logging();
    $lh->_initialize_bracket_notation_whitelist();

    return $lh;
}

#### we do this here so we can specify what we want done when a key is unknown ####
sub _initialize_unknown_phrase_logging {
    my $lh = shift;

    if ( defined $Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT ) {    # PPI NO PARSE - Only needed if loaded
        my $setter_cr = $lh->can("set_context_${Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT}") or do {    # PPI NO PARSE - Only needed if loaded
            die "Invalid \$Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT: “$Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT”!";    # PPI NO PARSE - Only needed if loaded
        };
        $setter_cr->($lh);
    }

    # Any other $Cpanel::Carp::OUTPUT_FORMAT values that mean "no markup or ANSI terminal escaping sequences"?
    # A value of 'suppress' is only applicaple to Carp context so if they call maketext they obviously want it output. ## no extract maketext
    elsif ( defined $Cpanel::Carp::OUTPUT_FORMAT ) {    # issafe
        if ( $Cpanel::Carp::OUTPUT_FORMAT eq 'xml' ) {    # issafe
            $lh->set_context_plain();                     # no HTML markup or ANSI escape sequences
        }
        elsif ( $Cpanel::Carp::OUTPUT_FORMAT eq 'html' ) {    # issafe
            $lh->set_context_html();                          # HTML
        }
    }

    $lh->{'use_external_lex_cache'} = 1;

    if ( exists $Cpanel::CPDATA{'LOCALE_LOG_MISSING'} && $Cpanel::CPDATA{'LOCALE_LOG_MISSING'} ) {
        $lh->{'_log_phantom_key'} = sub {
            my ( $lh, $key ) = @_;

            # TODO: incorporate into reporting system -> log, email, HTTP GET/POST, etc...

            my $chain      = '';
            my $base_class = $lh->get_base_class();
            foreach my $class ( $lh->get_language_class, $base_class ) {
                my $lex_path = $lh->get_cdb_file_path( $class eq $base_class ? 1 : 0 );
                next if !$lex_path;
                $chain .= "\tLOCALE: $class\n\tPATH: $lex_path\n";
                last if $class eq 'Cpanel::Locale::en' || $class eq 'Cpanel::Locale::en_us' || $class eq 'Cpanel::Locale::i_default';
            }

            my $pkg = $lh->get_language_tag();
            _logger->info( ( $Cpanel::Parser::Vars::file ? "$Cpanel::Parser::Vars::file ::" : '' ) . qq{ Could not find key via '$pkg' locale:\n\tKEY: '$key'\n$chain} );    # PPI NO PARSE -- module will already be there is we care about it

        };
    }
    return $lh;
}

our @DEFAULT_WHITELIST = qw(quant asis output current_year list_and list_or comment boolean datetime local_datetime format_bytes get_locale_name get_user_locale_name is_defined is_future join list_and_quoted list_or_quoted numerate numf);

sub _initialize_bracket_notation_whitelist {
    my $lh = shift;

    my @whitelist             = @DEFAULT_WHITELIST;
    my $custom_whitelist_file = Cpanel::Locale::Utils::Paths::get_custom_whitelist_path();

    if ( open( my $fh, '<', $custom_whitelist_file ) ) {
        while ( my $ln = readline($fh) ) {
            chomp $ln;
            push @whitelist, $ln if length($ln);
        }
        close $fh;
    }

    $lh->whitelist(@whitelist);
    return $lh;
}

# override this or otherwise "tiny" up since we probably don't want the full power of the very excellent DateTime
# sub datetime {}

## Cpanel specific methods ##

sub output_cpanel_error {
    my ( $lh, $position ) = @_;

    if ( $lh->context_is_ansi() ) {
        return "\e[1;31m" if $position eq 'begin';
        return "\e[0m"    if $position eq 'end';
        return '';
    }
    elsif ( $lh->context_is_html() ) {
        return qq{<p style="color:#FF0000">} if $position eq 'begin';
        return '</p>'                        if $position eq 'end';
        return '';
    }
    else {
        return '';    # e.g. $lh->context_is_plain()
    }
}

sub cpanel_get_3rdparty_lang {
    my ( $lh, $_3rdparty ) = @_;
    require Cpanel::Locale::Utils::3rdparty;

    # configured setting for current locale || corresponding value for current locale || current tag || 'en' (can't ever get to the last '||' but for good measure ...)
    return Cpanel::Locale::Utils::3rdparty::get_app_setting( $lh, $_3rdparty ) || Cpanel::Locale::Utils::3rdparty::get_3rdparty_lang( $lh, $_3rdparty ) || $lh->get_language_tag() || 'en';
}

sub cpanel_is_valid_locale {
    my ( $lh, $locale ) = @_;

    my %valid_locales = map { $_ => 1 } ( qw(en en_us i_default), $lh->list_available_locales );
    return $valid_locales{$locale} ? 1 : 0;
}

sub cpanel_get_3rdparty_list {
    my ($lh) = @_;
    require Cpanel::Locale::Utils::3rdparty;
    return Cpanel::Locale::Utils::3rdparty::get_3rdparty_list($lh);
}

sub cpanel_get_lex_path {
    my ( $lh, $path, $rv ) = @_;

    return if !defined $path || $path eq '' || substr( $path, -3 ) ne '.js';

    require Cpanel::JS::Variations;

    my $query = $path;
    $query = Cpanel::JS::Variations::get_base_file( $query, '-%s.js' );

    if ( defined $rv && index( $rv, '%s' ) == -1 ) {
        substr( $rv, -3, 3, '-%s.js' );
    }

    my $asset_path = $lh->get_asset_file( $query, $rv );

    return $asset_path if $asset_path && substr( $asset_path, -3 ) eq '.js' && index( $asset_path, '-' ) > -1;    # Only return a value if there is a localized js file here
    return;
}

sub tag_is_default_locale {
    my $tag = $_[1] || $_[0]->get_language_tag();
    return 1 if $tag eq 'en' || $tag eq 'en_us' || $tag eq 'i_default';
    return;
}

sub get_cdb_file_path {
    my ( $lh, $core ) = @_;
    my $class = $core ? $lh->get_base_class() : $lh->get_language_class();
    no strict 'refs';
    return
         $class eq 'Cpanel::Locale::en'
      || $class eq 'Cpanel::Locale::en_us'
      || $class eq 'Cpanel::Locale::i_default' ? $Cpanel::Locale::CDB_File_Path : ${ $class . '::CDB_File_Path' };
}

#Cpanel::LoadFile expects to be able to throw a Cpanel::Exception instance,
#but there are cases in this module where we want to avoid the localization
#that that module applies.
sub _slurp_small_file_if_exists_no_exception {
    my ($path) = @_;

    # Leave these alone in case there’s something that would break.
    # This gets called from exception-creating code, which has historically
    # been a not-infrequent source of headaches in that regard.
    local ( $!, $^E );

    open my $rfh, '<', $path or do {
        if ( $! != _ENOENT() ) {
            warn "open($path): $!";
        }

        return undef;
    };

    read $rfh, my $buf, 8192 or do {
        warn "read($path): $!";
    };

    return $buf;
}

# return "server_locale" tweak setting or nothing
my $_server_locale_file_contents;

sub get_server_locale {
    if ( exists $ENV{'CPANEL_SERVER_LOCALE'} ) {
        return $ENV{'CPANEL_SERVER_LOCALE'} if $ENV{'CPANEL_SERVER_LOCALE'} !~ tr{A-Za-z0-9_-}{}c;
        return undef;
    }
    if (%main::CPCONF) {
        return $main::CPCONF{'server_locale'} if exists $main::CPCONF{'server_locale'};
    }

    # Avoid loadcpconf here as we may be in the middle of an exception
    # which would result in a loop

    # We create server_locale on update so it should always be there.

    # We must NOT create a Cpanel::Exception here since that
    # code can call into where we are here. That means we don’t
    # call Cpanel::LoadFile.
    #
    # Fallback to cpanel.config no longer happens since the server_locale
    # file will be in place as of v70
    return ( $_server_locale_file_contents //= ( _slurp_small_file_if_exists_no_exception($SERVER_LOCALE_FILE) || '' ) );
}

sub _clear_cache {
    $_server_locale_file_contents = undef;
    return;
}

# Return the local for the user 'cpanel', as opposed to the Cpanel user.
sub get_locale_for_user_cpanel {
    if (%main::CPCONF) {
        return $main::CPCONF{'cpanel_locale'} if exists $main::CPCONF{'cpanel_locale'};
        return $main::CPCONF{'server_locale'} if exists $main::CPCONF{'server_locale'};
    }
    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();    # safe since we do not modify cpconf

    # At Dan's suggestion, we are planning to have the cpanel user's local settable.
    return $cpconf->{'cpanel_locale'} if $cpconf->{'cpanel_locale'};    # will not be autovivified, 0 and "" are invalid, if the value is invalid they will get 'en'
    return $cpconf->{'server_locale'} if $cpconf->{'server_locale'};    # will not be autovivified, 0 and "" are invalid, if the value is invalid they will get 'en'
    return;
}

sub cpanel_reinit_lexicon {
    my ($lh) = @_;
    $lh->cpanel_detach_lexicon();
    $lh->cpanel_attach_lexicon();
}

my $detach_locale_lex;

sub cpanel_detach_lexicon {
    my ($lh) = @_;
    my $locale = $lh->get_language_tag();
    no strict 'refs';

    undef $Cpanel::Locale::CDB_File_Path;
    if ( $locale ne 'en' && $locale ne 'en_us' && $locale ne 'i_default' ) {
        $detach_locale_lex = ${ 'Cpanel::Locale::' . $locale . '::CDB_File_Path' };
        undef ${ 'Cpanel::Locale::' . $locale . '::CDB_File_Path' };
    }

    untie( %{ 'Cpanel::Locale::' . $locale . '::Lexicon' } );
    untie %Cpanel::Locale::Lexicon;
}

sub cpanel_attach_lexicon {
    my ($lh) = @_;
    my $locale = $lh->get_language_tag();

    # This part of _real_get_handle() needs redone here
    $Cpanel::Locale::CDB_File_Path = Cpanel::Locale::Utils::init_lexicon( 'en', \%Cpanel::Locale::Lexicon, \$Cpanel::Locale::VERSION, \$Cpanel::Locale::Encoding );

    _make_alias_if_needed($locale);

    no strict 'refs';
    if ( defined $detach_locale_lex ) {
        ${ 'Cpanel::Locale::' . $locale . '::CDB_File_Path' } = $detach_locale_lex;
    }
    else {
        ${ 'Cpanel::Locale::' . $locale . '::CDB_File_Path' } = $Cpanel::Locale::CDB_File_Path;
    }

    my $file_path = $lh->get_cdb_file_path();
    return if !$file_path;
    return Cpanel::Locale::Utils::get_readonly_tie( $lh->get_cdb_file_path(), \%{ 'Cpanel::Locale::' . $locale . '::Lexicon' } );
}

sub is_rtl {
    my ($lh) = @_;

    return 'right-to-left' eq $lh->get_language_tag_character_orientation() ? 1 : 0;
}

# get_language_tag_character_orientation was the slowest part of whostmgr/roothtml before this was added
sub get_language_tag_character_orientation {
    if ( my $direction = $known_locales_character_orientation{ $_[1] || $_[0]->{'fallback_locale'} || $_[0]->get_language_tag() } ) {
        return 'right-to-left' if $direction == $RTL;
        return 'left-to-right';
    }
    $_[0]->SUPER::get_language_tag_character_orientation( @_[ 1 .. $#_ ] );
}

my $menu_ar;

sub get_locale_menu_arrayref {
    return $menu_ar if $menu_ar;
    require Cpanel::Locale::Utils::Display;
    $menu_ar = [ Cpanel::Locale::Utils::Display::get_locale_menu_hashref(@_) ];    # always array context to get all structs, properly uses other args besides object
    return $menu_ar;
}

my $non_existent;

sub get_non_existent_locale_menu_arrayref {
    return $non_existent if $non_existent;
    require Cpanel::Locale::Utils::Display;
    $non_existent = [ Cpanel::Locale::Utils::Display::get_non_existent_locale_menu_hashref(@_) ];    # always array context to get all structs, properly uses other args besides object
    return $non_existent;
}

sub _api1_maketext {
    require Cpanel::Locale::Utils::Api1;
    goto \&Cpanel::Locale::Utils::Api1::_api1_maketext;                                              ## no extract maketext
}

our $api1 = {
    'maketext' => {                                                                                  ## no extract maketext
        'function'        => \&_api1_maketext,                                                       ## no extract maketext
        'internal'        => 1,
        'legacy_function' => 2,
        'modify'          => 'inherit',
    },
};

sub current_year {
    return (localtime)[5] + 1900;    # we override datetime() so we can't use the internal current_year()
}

sub local_datetime {
    my ( $lh, $epoch, $format ) = @_;
    my $timezone = $ENV{'TZ'} // do {
        require Cpanel::Timezones;
        Cpanel::Timezones::calculate_TZ_env();
    };
    return $lh->datetime( $epoch, $format, $timezone );
}

sub datetime {
    my ( $lh, $epoch, $format, $timezone ) = @_;
    require Cpanel::Locale::Utils::DateTime;

    #ISO format
    if ( $epoch && $epoch =~ tr<0-9><>c ) {
        require    # do not include it in updatenow.static
          Cpanel::Validate::Time;
        Cpanel::Validate::Time::iso_or_die($epoch);

        require Cpanel::Time::ISO;
        $epoch = Cpanel::Time::ISO::iso2unix($epoch);
    }

    return Cpanel::Locale::Utils::DateTime::datetime( $lh, $epoch, $format, $timezone );
}

sub get_lookup_hash_of_multi_epoch_datetime {
    my ( $lh, $epochs_ar, $format, $timezone ) = @_;
    require Cpanel::Locale::Utils::DateTime;
    return Cpanel::Locale::Utils::DateTime::get_lookup_hash_of_multi_epoch_datetime( $lh, $epochs_ar, $format, $timezone );
}

sub get_locale_name_or_nothing {
    my ( $locale, $name, $in_locale_tongue ) = @_;
    $name ||= $locale->get_language_tag();

    if ( index( $name, 'i_' ) == 0 ) {
        require Cpanel::DataStore;
        my $i_locales_path = Cpanel::Locale::Utils::Paths::get_i_locales_config_path();
        my $i_conf         = Cpanel::DataStore::fetch_ref("$i_locales_path/$name.yaml");

        return $i_conf->{'display_name'} if $i_conf->{'display_name'};
    }
    else {
        my $real = $locale->get_language_tag_name( $name, $in_locale_tongue );
        return $real if $real;
    }

    return;
}

sub get_locale_name_or_tag {
    return $_[0]->get_locale_name_or_nothing( $_[1], $_[2] ) || $_[1] || $_[0]->get_language_tag();
}

*get_locale_name = *get_locale_name_or_tag;    # for shorter BN

sub get_user_locale {
    return $Cpanel::CPDATA{'LOCALE'} if $Cpanel::CPDATA{'LOCALE'};
    require Cpanel::Locale::Utils::User;       # probably a no-op but just in case since its loading is conditional
    return Cpanel::Locale::Utils::User::get_user_locale();
}

sub get_user_locale_name {
    require Cpanel::Locale::Utils::User;       # probably a no-op but just in case since its loading is conditional
    return $_[0]->get_locale_name_or_tag( Cpanel::Locale::Utils::User::get_user_locale( $_[1] ) );
}

=head2 set_user_locale(LH, CODE)

Set the current users locale by the ISO 3166 language code for the users.

Important: The new locale will be available only in new processes.

=head3 ARGUMENTS

=over

=item LH - Cpanel::Locale

Reference to the current locale handle.

=item CODE - THE ISO 3166 language code. May also include a country code and/or region code.

    Example    | Description
    -------------------------------------------
    en         | English
    nb         | Norwegian Bokmål
    es         | Spanish
    es_es      | Spanish as spoken in Spain.
    vi         | Vietnamese

=back

=head3 RETURNS

1 on success

=head3 EXCEPTIONS

=over

=item Unrecognized locale

=item Various IO exceptions

=back

=head3 EXAMPLE

Set the current users locale to Chinese

    use Cpanel::Locale ();
    my $lh = Cpanel::Locale::lh();
    eval {
        $lh->set_user_locale('zh_cn');
    };
    if (my $exception = $@) {
        print STDERR "EXCEPTION: $exception\n";
    }
    else {
        # success setting the locale.
        print STDOUT "SUCCESS";
    }

=cut

sub set_user_locale {
    my ( $locale, $country_code ) = @_;

    if ($country_code) {
        my $language_name = $locale->lang_names_hashref();

        if ( exists $language_name->{$country_code} ) {
            require Cpanel::Locale::Utils::Legacy;
            require Cpanel::Locale::Utils::User::Modify;

            my $language = Cpanel::Locale::Utils::Legacy::get_best_guess_of_legacy_from_locale($country_code);
            if ( Cpanel::Locale::Utils::User::Modify::save_user_locale( $country_code, $language, $Cpanel::user ) ) {
                return 1;
            }

        }
    }

    # TODO: Need to add a real exception class for this. Maybe Cpanel::Exception::UnknownLocale
    die Cpanel::Exception::create_raw( "Empty", $locale->maketext("Unable to set locale, please specify a valid country code.") );
}

=head2 get_locales()

Get a list of supported locales for the server.

=head3 RETURNS

An array with one or more available locale structures
each with the following fields:

=over

=item locale_name - String

short name for the locale

=item direction - String

one of 'ltr' or 'rtl'

=item locale - String

The ISO 3166 locale code. May also include the country or region code.

    Example    | Description
    -------------------------------------------
    en         | English
    nb         | Norwegian Bokmål
    es         | Spanish
    es_es      | Spanish as spoken in Spain.
    vi         | Vietnamese

=item name - String

The name of language in the current locale.

=back

=head3 EXAMPLE

    use Cpanel::Locale ();
    my $lh = Cpanel::Locale::lh();
    my $available = $lh->get_locales();

=cut

sub get_locales {

    my $locale = shift;
    my @listing;
    my ( $names, $local_names ) = $locale->lang_names_hashref();

    foreach ( keys %{$names} ) {
        push @listing, {
            locale     => $_,
            name       => $names->{$_},
            local_name => $local_names->{$_},
            direction  => ( !defined $known_locales_character_orientation{$_} || $known_locales_character_orientation{$_} == $LTR ) ? 'ltr' : 'rtl'
        };
    }

    return \@listing;

}

my $api2_lh;

sub api2_get_user_locale {
    $api2_lh ||= Cpanel::Locale->get_handle();
    return ( { 'locale' => $api2_lh->get_user_locale() } );
}

sub api2_get_user_locale_name {
    $api2_lh ||= Cpanel::Locale->get_handle();
    return ( { 'name' => $api2_lh->get_user_locale_name() } );
}

sub api2_get_locale_name {
    $api2_lh ||= Cpanel::Locale->get_handle();

    # We can usually avoid unpacking to a hash here since:
    #    * this function is only interested in 1 (optional) piece of info
    #    * api2 args are (key=value[,ad=infinum])
    # that means that, usually, index 1 is the value we are looking for.
    # The only trick is if, for some reason, the caller passes in more
    # arguments than are necessary.
    my $tag = ( scalar @_ > 2 ) ? {@_}->{'locale'} : $_[1];

    return ( { 'name' => $api2_lh->get_locale_name_or_tag($tag) } );
}

sub api2_get_encoding {
    $api2_lh ||= Cpanel::Locale->get_handle();
    return ( { 'encoding' => $api2_lh->encoding() } );
}

sub api2_numf {
    my %args = @_;
    $api2_lh ||= Cpanel::Locale->get_handle();
    return ( { 'numf' => $api2_lh->numf( $args{number}, $args{max_decimal_places} ) } );
}

sub api2_get_html_dir_attr {
    $api2_lh ||= Cpanel::Locale->get_handle();

    # We can avoid unpacking to a hash here since this api2 function is not
    # interested in anything other than the in-use locale's dir attribute.
    # That is why there are no arguments passed to get_html_dir_attr()
    return ( { 'dir' => $api2_lh->get_html_dir_attr() } );
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    get_locale_name      => $allow_demo,
    get_encoding         => $allow_demo,
    get_html_dir_attr    => $allow_demo,
    get_user_locale      => $allow_demo,
    get_user_locale_name => $allow_demo,
    numf                 => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

my $global_lh;

=head2 lh()

Get the global locale singleton.  This is generally faster to call than C<get_handle> because it only does the setup once.
If your program is not going to switch users you should use this function to get the locale handle.
If your program is going to switch users, you must use C<get_handle> instead.

This should be safe to use in C<Cpanel::Template::Plugin::*>, C<Cpanel::API::*>.

It is not advisable to use this method in something like C<bin/autossl_check.pl> because it switches between users.

=head3 RETURNS

=over

=item C<Cpanel::Locale> object

This returns a locale handle.

=back

=head3 EXAMPLE

Note this is a package method, not an instance method.

 use Cpanel::Locale ();
 my $lh = Cpanel::Locale::lh();

=cut

sub lh {
    return ( $global_lh ||= Cpanel::Locale->get_handle() );
}

# Allow exporting lh() without using Exporter.pm
sub import {
    my ( $package, @args ) = @_;
    my ($namespace) = caller;
    if ( @args == 1 && $args[0] eq 'lh' ) {
        no strict 'refs';    ## no critic(ProhibitNoStrict)
        my $exported_name = "${namespace}::lh";
        *$exported_name = \*lh;
    }
}

# Do no use LoadModule as we do not have exception handling here
sub _load_carp {
    if ( !$INC{'Cpanel/Carp.pm'} ) {

        #prevent $@-clobbering problems with overload.pm.
        local $@;

        eval 'require Cpanel::Carp; 1;' or die $@;    # hide from perlcc
    }

    return;
}

sub user_feedback_text_for_more_locales {
    require Cpanel::Version;

    my $locale  = Cpanel::Locale->get_handle();
    my $version = Cpanel::Version::get_version_full();

    # The go link system doesn't support dynamically passing query parmaters, so the link is hardcoded.
    my $survey_url = 'https://webpros.typeform.com/changeLng?utm_source=cpanel-changelanguage&cpanel_productversion=' . $version;

    return $locale->maketext( "Don’t see your language of choice? Take our [output,url,_1,Language Support Feedback Survey,class,externalLink,target,Language Survey] to let us know your preferences.", $survey_url );
}

1;
