package Cpanel::Template::Unauthenticated;

# cpanel - Cpanel/Template/Unauthenticated.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

require base;    #needed for Template loading

use Cpanel::App                                 ();
use Cpanel::Debug                               ();
use Cpanel::LoadModule                          ();
use Cpanel::LoginTheme                          ();
use Cpanel::Template::Unauthenticated::Provider ();    # PPI USE OK - Indirectly used when handed to Template
use Cpanel::Template::Shared                    ();

use Cpanel::Template::Plugin::JSON ();                 # PPI USE OK -- hide from parser since template plugin namespaces are funny.
use Cpanel::Template::Plugin::HTTP ();                 # PPI USE OK -- hide from parser since template plugin namespaces are funny.
use Cpanel::PublicContact          ();

our @ISA = ('Template');

our $ROOT_TEMPLATE_COMPILE_FOLDER       = "/var/cpanel/template_compiles";
our $LOGIN_USER_HOME_FOLDER             = "/var/cpanel/userhomes/cpanellogin/";
our $LOGIN_USER_TEMPLATE_COMPILE_FOLDER = "/var/cpanel/userhomes/cpanellogin/template_compiles";
our $DOCROOT                            = '/usr/local/cpanel/base';

sub new {
    my ( $class, %opts ) = @_;

    load_required_modules() if ( !exists $INC{'Template/Config.pm'} || !exists $INC{'Template.pm'} );

    my $docroot = $DOCROOT;

    if ( exists $opts{'INCLUDE_PATH'} ) {
        if ( ref $opts{'INCLUDE_PATH'} ) {
            push @{ $opts{'INCLUDE_PATH'} }, $docroot;
        }
        else {
            $opts{'INCLUDE_PATH'} = [ $opts{'INCLUDE_PATH'}, $docroot ];
        }
    }
    else {
        $opts{'INCLUDE_PATH'} = $docroot;
    }

    if ( $> == 0 ) {
        $opts{'COMPILE_DIR'} = $ROOT_TEMPLATE_COMPILE_FOLDER;
        if ( !-e $opts{'COMPILE_DIR'} ) {
            mkdir( $opts{'COMPILE_DIR'}, 0700 );
        }
    }
    elsif ( -w $LOGIN_USER_TEMPLATE_COMPILE_FOLDER ) {
        $opts{'COMPILE_DIR'} = $LOGIN_USER_TEMPLATE_COMPILE_FOLDER;
    }
    elsif ( -w $LOGIN_USER_HOME_FOLDER ) {
        if ( mkdir( $LOGIN_USER_TEMPLATE_COMPILE_FOLDER, 0700 ) ) {
            $opts{'COMPILE_DIR'} = $LOGIN_USER_TEMPLATE_COMPILE_FOLDER;
        }
    }

    local $Template::Config::PROVIDER = 'Cpanel::Template::Unauthenticated::Provider';

    if ( ref $opts{'PLUGIN_BASE'} ) {
        push @{ $opts{'PLUGIN_BASE'} }, 'Cpanel::Template::Plugin';
    }
    else {
        $opts{'PLUGIN_BASE'} = [ $opts{'PLUGIN_BASE'} || (), 'Cpanel::Template::Plugin' ];
    }

    {
        *Template::Provider::_template_content = *Cpanel::Template::Shared::_template_content;

    }

    my $self = bless $class->SUPER::new(%opts), $class;

    $self->{'_docroot'}       = $docroot;
    $self->{'locale_context'} = $opts{'locale_context'};

    return $self;
}

sub load_required_modules {
    eval {
        require Cpanel::Locale::Utils::SpecialCase;    # PPI USE OK - used below
        require Cpanel::Locale;
        require Cpanel::MagicRevision;                 # PPI USE OK - used below

        require Template;
        require Template::Plugin;
        require Template::Iterator;
        require Template::Context;
        require Template::Plugins;
        require Template::Filters;
    };
    if ($@) {
        Cpanel::Debug::log_warn($@);
    }

    no warnings 'redefine';
####
#### The below avoids importing File:: which was 15% of cPanel's startup time
####
    *Template::Document::write_perl_file = \&Cpanel::Template::Unauthenticated::write_perl_file;

    return;
}

sub process {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $this, $file, $opts_hr ) = splice( @_, 0, 3 );

    return if !length($file);

    $opts_hr ||= {};
    my $locale = Cpanel::Locale::Utils::SpecialCase::get_unauthenticated_user_handle();    # PPI NO PARSE: Loaded in new(), via load_required_modules()

    local *Cpanel::Locale::lh;
    {
        no warnings 'redefine';
        *Cpanel::Locale::lh = sub { return $locale };
    }

    #set_context() cares whether -t-STDIN exists, so we need to be sure
    #to preserve the state of that key in the hash exactly.
    local $locale->{'-t-STDIN'} = $locale->{'-t-STDIN'} if $this->{'locale_context'};
    if ( $this->{'locale_context'} ) {
        $locale->set_context( $this->{'locale_context'} );
    }

    my $show_current_locale = !$opts_hr->{'_chosen_locale'} || $opts_hr->{'_chosen_locale'} ne $locale->get_language_tag();

    # ** WARNING **: Do not call maketext inside of this sub                  ## no extract maketext
    # without wrapping it in a sub {} or it may get cached in the wrong
    # locale

    @{$opts_hr}{
        'ENV_REQUEST_URI',
        'https',
        'locale',
        'display_locales',
        'MagicRevision',
        'get_theme_url',
        'login_messages',
        'CPANEL',    # For compatibility with cjt2_header_include.tt
        'calculate_magic_mtime',
        'calculate_magic_lex_mtime',
        'get_required_password_strength',
      } = (
        $ENV{'REQUEST_URI'},
        ( ( $ENV{'HTTPS'} || q<> ) eq 'on' ) ? 1 : 0,
        $locale,
        sub { scalar $opts_hr->{'_get_locale_tags_and_names'}( $locale, $show_current_locale ) },
        \&Cpanel::MagicRevision::calculate_magic_url,    # PPI NO PARSE: Loaded in new(), via load_required_modules()
        \&Cpanel::LoginTheme::get_login_url,
        sub { return _login_messages( $opts_hr, $locale ) },

        {
            is_debug_mode_enabled => \&_is_debug_mode_enabled,
            get_account_type      => \&_get_account_type,
            FORM                  => { cache_bust => _is_cache_bust_enabled() }
        },
        \&Cpanel::MagicRevision::get_magic_revision_mtime,        # PPI NO PARSE: Loaded in new(), via load_required_modules()
        \&Cpanel::MagicRevision::get_magic_revision_lex_mtime,    # PPI NO PARSE: Loaded in new(), via load_required_modules()
        sub {
            Cpanel::LoadModule::load_perl_module('Cpanel::PasswdStrength::Check');
            goto \&Cpanel::PasswdStrength::Check::get_required_strength;
        }
      );
    {
        BEGIN { ${^WARNING_BITS} = ''; }                          ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings
        local $INC{'File/Path.pm'} = __FILE__;
        local *File::Path::mkpath = sub {
            require Cpanel::SafeDir::MK;
            goto \&Cpanel::SafeDir::MK::safemkdir;
        };

        my $output = shift @_;
        $$output .= $this->_trial_banner($opts_hr);

        my $result = $this->SUPER::process( $file, $opts_hr, $output );
        return $result;
    }
}

sub write_perl_file {
    my ( $class, $file, $content ) = @_;
    my ( $fh, $tmpfile );

    Cpanel::LoadModule::load_perl_module('Cpanel::Rand');
    return $class->error("Invalid filename: $file")
      unless $file =~ m/^(.+)$/s;

    eval {
        my @DIR = split( /\//, $file );
        pop(@DIR);
        my $dirname = join( '/', @DIR );
        ( $tmpfile, $fh ) = Cpanel::Rand::get_tmp_file_by_name( $dirname . '/template' );    # audit case 46806 ok
        $tmpfile =~ tr{/}{}s;
        if ($tmpfile) {
            my $perlcode = $class->as_perl($content) || die $!;
            if ( $Template::Document::UNICODE
                && Template::Document::is_utf8($perlcode) ) {
                $perlcode = "use utf8;\n\n$perlcode";
                binmode $fh, ":encoding(UTF-8)";
            }
            print {$fh} $perlcode;
            close($fh);
        }
    };
    return $class->error($@) if $@;
    return rename( $tmpfile, $file )
      || $class->error($!);
}

sub _is_debug_mode_enabled {
    require Cpanel::Form;
    my $form = $Cpanel::Form::Parsed_Form_hr;
    return ( $form->{'debug'} || $Cpanel::CPVAR{'debug'} ) ? 1 : 0;
}

sub _get_account_type {
    require Cpanel::Form;
    my $form = $Cpanel::Form::Parsed_Form_hr;
    return $form->{'account_type'} || "";
}

sub _is_cache_bust_enabled {
    require Cpanel::Form;
    my $form = $Cpanel::Form::Parsed_Form_hr;
    return ( $form->{'cache_bust'} || $Cpanel::CPVAR{'cache_bust'} ) ? 1 : 0;
}

sub _login_messages {
    my ( $opts_hr, $locale ) = @_;
    my $msg_code = $opts_hr->{'msg_code'};
    my $msg_code_value;
    if ($msg_code) {
        $msg_code_value = _get_locale_string_for_msg_code( $msg_code, $locale, $opts_hr );
    }

    my $pc_url = Cpanel::PublicContact->get('root');
    $pc_url &&= $pc_url->{'url'};

    my $internal_err_msg;
    if ($pc_url) {
        $internal_err_msg = $locale->maketext( 'An internal error occurred. If this condition persists, [output,url,_1,contact the system administrator].', $pc_url );
    }
    else {
        $internal_err_msg = $locale->maketext('An internal error occurred. If this condition persists, contact the system administrator.');
    }

    return {
        #
        # These login messages can be displayed at any time so we must always send them
        #
        ajax_timeout   => $locale->maketext('The connection timed out. Please try again.'),
        read_below     => $locale->maketext('Read the important information below.'),
        success        => $locale->maketext('Login successful. Redirecting …'),
        invalid_login  => $locale->maketext('The login is invalid.'),
        network_error  => $locale->maketext('A network error occurred during your login request. Please try again. If this condition persists, contact your network service provider.'),
        no_username    => $locale->maketext('You must specify a username to log in.'),
        authenticating => $locale->maketext('Authenticating …'),
        session_locale => $locale->maketext('The desired locale has been saved to your browser. To change the locale in this browser again, select another locale on this screen.'),
        internal_error => $internal_err_msg,

        # Only create the locale string for the msg_code
        # that we requested in order to avoid the
        # expense of making every possible locale string
        # on every login page

        ( $msg_code && $msg_code_value ? ( $msg_code => $msg_code_value ) : () )
    };
}

sub _get_locale_string_for_msg_code {
    my ( $msg_code, $locale, $opts_hr ) = @_;

    #msg_code

    if ( $msg_code eq 'prevented_xfer' ) {
        return $locale->maketext('The system could not transfer this session because you did not access this service over a secure connection. Please log in now to continue.');
    }
    elsif ( $msg_code eq 'invalid_username' ) {
        return $locale->maketext('The submitted username is invalid.');
    }
    elsif ( $msg_code eq 'token_missing' ) {
        return $locale->maketext('The security token is missing from your request.');
    }
    elsif ( $msg_code eq 'token_incorrect' ) {
        return $locale->maketext('The security token in your request is invalid.');
    }
    elsif ( $msg_code eq 'changed_ip' ) {
        return $locale->maketext('Your IP address has changed. Please log in again.');
    }
    elsif ( $msg_code eq 'expired_session' ) {
        return $locale->maketext('Your session has expired. Please log in again.');
    }
    elsif ( $msg_code eq 'invalid_session' ) {
        return $locale->maketext('Your session cookie is invalid. Please log in again.');
    }
    else {

        # OpenID Connect messages section
        my $oidc_provider         = $opts_hr->{'openid_provider_display_name'} || q<>;
        my $preferred_username    = $opts_hr->{'preferred_username'}           || q<>;
        my $if_persists           = $locale->maketext('If this condition persists, contact your system administrator.');
        my $log_in_again_text     = $locale->output_url( $opts_hr->{'openid_provider_link'}, $locale->maketext( 'Log in to [_1] again.', $oidc_provider ) );
        my $failed_to_communicate = $locale->maketext( 'The server failed to communicate with [_1].', $oidc_provider );

        if ( $msg_code eq 'link_account' ) {
            return $locale->maketext('The system will link your account to the external authentication server.') . ' ' . $locale->maketext('Log in again.');
        }
        elsif ( $msg_code eq 'missing_openid_code' ) {
            return $locale->maketext( '[_1] did not return an authorization code.', $oidc_provider ) . " $log_in_again_text $if_persists";
        }
        elsif ( $msg_code eq 'missing_openid_state' ) {
            return $locale->maketext( '[_1] did not send back the state of the request.', $oidc_provider ) . " $log_in_again_text $if_persists";
        }
        elsif ( $msg_code eq 'openid_access_denied' ) {
            return $locale->maketext( '[_1] denied access to information that this system needs in order to authenticate you. [output,url,_2,Log in again], but authorize this server to access the information that it requests.', $oidc_provider, $opts_hr->{'openid_provider_link'} );
        }
        elsif ( $msg_code eq 'openid_communication' ) {
            return "$failed_to_communicate $log_in_again_text $if_persists";
        }
        elsif ( $msg_code eq 'openid_communication_no_login' ) {
            return "$failed_to_communicate $if_persists";
        }
        elsif ( $msg_code eq 'openid_missing_id_token' ) {
            return $locale->maketext( '[_1] did not send back the [asis,ID] token.', $oidc_provider ) . " $log_in_again_text $if_persists";
        }
        elsif ( $msg_code eq 'openid_provider_misconfigured' ) {
            return $locale->maketext('The system failed to complete an [asis,OpenID Connect] authentication due to a possible misconfiguration.') . " $if_persists";

        }
        elsif ( $msg_code eq 'openid_unable_to_get_access_token' ) {
            return $locale->maketext( 'The system failed to retrieve an access token from [_1].', $oidc_provider ) . " $log_in_again_text $if_persists";
        }
        elsif ( $msg_code eq 'openid_access_token_expired' ) {
            return $locale->maketext('Your [asis,OpenID Connect] session has expired.') . " $log_in_again_text";
        }
        elsif ( $msg_code eq 'invalid_openid_external_validation_token' ) {
            return $locale->maketext( '[_1] did not return the correct validation token.', $oidc_provider ) . " $log_in_again_text $if_persists";

        }
        elsif ( $msg_code eq 'oidc_received_error' ) {
            return $locale->maketext( 'The system received an error from [_1]: [_2]', $oidc_provider, $opts_hr->{'oidc_error'} || q<> );

        }
        elsif ( $msg_code eq 'user_selection' ) {
            my $cpanel_context_display_name = Cpanel::App::get_context_display_name();

            return $locale->maketext( 'The “[_1]” account “[_2]” links to multiple “[_3]” accounts. Select the “[_3]” account that you wish to access.', $oidc_provider, $preferred_username, $cpanel_context_display_name );
        }

        # End OpenID Connect messages section
    }

    return;

}

sub _trial_banner {
    my ( $self, $opts_hr ) = @_;

    my $banner = '';
    if ( $opts_hr->{'_is_trial'} ) {    # The lack of localization is intentional
        $banner = '<div style="background-color: #FCF8E1; padding: 10px 30px 10px 50px; border: 1px solid #F6C342; margin-bottom: 20px; border-radius: 2px; color: black;"><div style="width: 250px; margin: 0 auto;">This server uses a trial license</div></div>';
    }
    return $banner;
}
1;
