package Cpanel::iContact::Class;

# cpanel - Cpanel/iContact/Class.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# An object-oriented wrapper around Cpanel::iContact that interacts with
# on-disk templates. This allows admins (and, potentially, eventually
# resellers) to customize the notices.
#
# Each type of notice should be defined in its own subclass. See the
# subclassing interface described below.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use Cpanel::ConfigFiles              ();
use Cpanel::Exception                ();
use Cpanel::Finally                  ();
use Cpanel::ForkAsync                ();
use Cpanel::LoadModule               ();
use Cpanel::Debug                    ();
use Cpanel::Validate::FilesystemPath ();
use Cpanel::FileUtils::Open          ();
use Cpanel::AcctUtils::Account       ();
use Cpanel::StringFunc::Trim         ();

#See comments below about HTML::FormatText.
my $FAUX_LINE_WRAP_SUPPRESSION = 5_000;
our $DEFAULT_NUMBER_OF_LINES_FOR_PREVIEW = 10;

my $DEFAULT_BODY_FORMAT = 'html';

#if attach_files is provided we also provide log_preview
my @body_formats = ( $DEFAULT_BODY_FORMAT, 'text' );
my @default_args = (
    'attach_files',
    'to',
    'host_server',
    'domain',
    'sent_to_root',
    'notification_cannot_be_disabled',
    'notification_targets_user_account',
    'subaccount',
    'use_alternate_email',
    'team_account'
);
my @POTENTIALLY_STUBBED_MODULES = qw(Scalar::Util File::Spec Cpanel::Hash);

my $system_info_template_vars;
my $procdata_for_template_ar;

# useful for writing “small” tests:
our $ALLOW_NONROOT_INSTANTIATION;

#----------------------------------------------------------------------

#Used for blocking sends
sub _do_in_foreground {
    my ($todo_cr) = @_;
    try {

        # Make sure the redirection is restricted to this scope, as otherwise
        # you'll have STDOUT & STDERR forever trapped until program exit.
        # This is fine within '_do_in_daemon' as such, but not here.
        require Cpanel::RedirectFH;
        Cpanel::FileUtils::Open::sysopen_with_real_perms( my $log_fh, $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log', 'O_WRONLY|O_APPEND|O_CREAT', 0600 );
        my $redirect_std = Cpanel::RedirectFH->new( \*STDOUT => $log_fh );
        my $redirect_err = Cpanel::RedirectFH->new( \*STDERR => $log_fh );
        $todo_cr->();
    }
    catch {
        my $err = $_;
        Cpanel::Debug::log_warn( "icontact/class error: " . ( eval { $err->to_string() } || $err ) );
    };
    return 1;
}

#Used for mocking in tests.
sub _do_in_daemon {
    my ($todo_cr) = @_;

    return Cpanel::ForkAsync::do_in_child(
        sub {
            try {
                ####
                # The next two calls are unchecked because it cannot be captured when running as a daemon
                Cpanel::FileUtils::Open::sysopen_with_real_perms( \*STDERR, $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log', 'O_WRONLY|O_APPEND|O_CREAT', 0600 );
                open( STDOUT, '>&', \*STDERR ) || warn "Failed to redirect STDOUT to STDERR";
                ####
                $todo_cr->();
            }
            catch {
                my $err = $_;
                Cpanel::Debug::log_warn( "icontact/class error: " . ( eval { $err->to_string() } || $err ) );
            };
        }
    );
}

our $_DEFAULT_TEMPLATES_DIR = "$Cpanel::ConfigFiles::CPANEL_ROOT/etc/icontact_templates";
our $_CUSTOM_TEMPLATES_DIR  = '/var/cpanel/templates/icontact_templates';

sub _generate_log_preview_from_log {
    my ( $self, $log, $number_of_preview_lines, $error_lines, $last_line_number_used ) = @_;

    my $locale                  = $self->locale();
    my $unavailable_log_message = $locale->maketext('The log is not available.');

    #if the log doesn't exist we should just bail immediately
    return $unavailable_log_message if !$log;

    require Cpanel::Output::Formatted::HTMLEmail;

    # Create a preview to attach in the message
    # using the last 10 lines of the log
    my $log_preview = q{};
    my $output      = open my ($log_fh), '>', \$log_preview or die "cannot create scalar file handle for log preview";
    my $output_obj  = Cpanel::Output::Formatted::HTMLEmail->new( 'filehandle' => $log_fh );
    my @lines       = split( m{\n}, $log );

    # only take care of the last lines after the last seen error
    @lines = splice( @lines, $last_line_number_used - 1 ) if $last_line_number_used && $last_line_number_used < scalar @lines;

    my $number_of_lines = scalar @lines;

    $number_of_preview_lines ||= $DEFAULT_NUMBER_OF_LINES_FOR_PREVIEW;

    # try to add 5 error lines on top of the preview
    my @extract;
    if ( $number_of_preview_lines >= 10 && ref $error_lines eq 'ARRAY' && scalar @$error_lines ) {
        push @extract, '...';                                             # start with '...''
        push @extract, splice( @$error_lines, 0, 5 );
        push @extract, '...' if $extract[-1] && $extract[-1] ne '...';    # add '...' separator before the end of the file
        $number_of_preview_lines -= scalar(@extract);
    }

    # add the last X lines from the log
    $number_of_lines = $number_of_preview_lines if $number_of_lines > $number_of_preview_lines;
    push @extract, splice( @lines, ( -1 * $number_of_lines ), $number_of_lines );

    foreach my $line (@extract) {
        $output_obj->output_highlighted_message($line);
    }

    $log_preview ||= $unavailable_log_message;
    return $log_preview;
}

sub locale {
    my ($self) = @_;

    require Cpanel::Locale;
    return scalar Cpanel::Locale->get_handle( $self->{'_locale'} || () );
}

#----------------------------------------------------------------------

#----------------------------------------------------------------------
# Subclass interface
#
# Any args that new() receives get put into $self->{'_opts'};
# retrieve them from there in _template_args() and _icontact_args(),
# and return them to pass them onto the template or to the icontact()
# backend.
#----------------------------------------------------------------------
sub _required_args {
    return;    #should return a list.
}

sub _template_args {
    my ($self) = @_;

    my %template_args = ( map { $_ => $self->{'_opts'}{$_} } grep { length $self->{'_opts'}{$_} } @default_args );

    if ( $self->{'_opts'}{'attach_files'} && ref $self->{'_opts'}{'attach_files'} eq 'ARRAY' ) {
        $template_args{'log_preview'}      = [];
        $template_args{'log_preview_name'} = [];
        foreach my $file_count ( 0 .. $#{ $self->{'_opts'}{'attach_files'} } ) {
            my $attach_file = $self->{'_opts'}{'attach_files'}->[$file_count];

            next if !ref $attach_file;
            my $log = ref $attach_file->{'content'} ? ${ $attach_file->{'content'} } : $attach_file->{'content'};    #

            # get failed events
            my $after_line = 0;
            $after_line = $self->{'_opts'}->{events_after_line} if ref $self->{'_opts'} && $self->{'_opts'}->{events_after_line};

            my $preview_lines = $attach_file->{'number_of_preview_lines'};

            require Cpanel::Logs::ErrorEvents;
            my ( $events, $error_lines, $last_line_number_used ) = Cpanel::Logs::ErrorEvents::extract_events_from_log( log => $log, after_line => $after_line, max_lines => $preview_lines );

            $template_args{'failed_events'}->[$file_count] = $events;

            $template_args{'log_preview'}->[$file_count]      = $self->_generate_log_preview_from_log( $log, $preview_lines, $error_lines, $last_line_number_used );    #
            $template_args{'log_preview_name'}->[$file_count] = $attach_file->{'name'} || '';

        }
    }

    return (
        ( $self->_has_valid_username() ? ( 'username' => $self->{'_opts'}{'username'} ) : () ),
        %template_args,
    );
}

sub _has_valid_username {
    my ($self) = @_;

    if ( length $self->{'_opts'}{'username'} ) {
        if ( $self->{'_opts'}{'username'} =~ m{@} ) {
            require Cpanel::AcctUtils::Lookup::MailUser::Exists;
            if ( Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist( $self->{'_opts'}{'username'} ) ) {
                return 1;    #webmail user
            }
        }
        elsif ( Cpanel::AcctUtils::Account::accountexists( $self->{'_opts'}{'username'} ) ) {
            return 1;
        }
    }

    return 0;
}

#NOTE: We intelligently handle "attach_files" within this.
sub _icontact_args {
    my ($self) = @_;

    #
    # Only use the hostname at the beginning of the subject if notification is
    # about the server.
    #
    # notification_targets_user_account means that the notification is going to
    # the user about something on their account.  This should never be set
    # when we are contacting root
    #
    # All notifications that go to the contact email address for the server in Edit setup should be able to be sorted with a filter
    # /^[HOSTNAME]/
    # All notifications that go to a reseller about a WHM/Admin action should be able to be sorted with a filter
    # /^[HOSTNAME]/
    # All notifications that come to the user about their account should be able to be sorted with a filter
    # /^[DOMAIN]/
    #
    if ( $self->{'_opts'}{'sent_to_root'} && $self->{'_opts'}{'notification_targets_user_account'} ) {
        die "Implementation error: notification_targets_user_account should never be set for notifications going to 'root'";
    }

    my @subject_prepend = (
        $self->{'_opts'}{'notification_targets_user_account'}
        ? (
            'prepend_domain_subject'   => 1,
            'prepend_hostname_subject' => 0
          )
        : (
            'prepend_domain_subject'   => 0,
            'prepend_hostname_subject' => 1
        ),
    );
    return (
        @subject_prepend,
        ( $self->_has_valid_username() ? ( 'username' => $self->{'_opts'}{'username'} ) : () ),
        map { $_ => $self->{'_opts'}{$_} } grep { length $self->{'_opts'}{$_} } @default_args
    );
}

sub _get_system_info_template_vars {
    my ($self) = @_;

    # This cache is probably only useful in the few situations when we send multiple messages
    return $system_info_template_vars if keys %$system_info_template_vars;

    require Cpanel::iContact::Utils;
    return $system_info_template_vars = { Cpanel::iContact::Utils::system_info_template_vars() };
}

sub _get_procdata_for_template {
    my ($self) = @_;

    # This cache is probably only useful in the few situations when we send multiple messages
    return $procdata_for_template_ar if ref $procdata_for_template_ar;

    require Cpanel::iContact::Utils;
    return $procdata_for_template_ar = Cpanel::iContact::Utils::procdata_for_template();
}

#----------------------------------------------------------------------

#Named arguments will vary according to subclass; the following are always
#understood:
#
#   body_format - (optional) Can be "html" (default) or "text"
#       If "text", only text will be included in the message.
#       If "html", both HTML and text will be included
#       in the message via multipart/alternative, but HTML will
#       be preferred.
#
# WARNING: This will send the message as soon as the object is created.
sub new {
    my ( $class, %opts ) = @_;

    if ( !$ALLOW_NONROOT_INSTANTIATION && $> != 0 ) {
        die "$class must be instantiated as the super user.";
    }

    my $body_format = delete $opts{'body_format'} || $DEFAULT_BODY_FORMAT;
    if ( !grep { $_ eq $body_format } @body_formats ) {
        die "“body_format” can only be: @body_formats!";
    }

    $class->_verify_required_args(%opts);

    my $self = {
        _body_format => $body_format,
        _opts        => \%opts,
    };

    if ( !length $self->{'_opts'}{'sent_to_root'} ) {
        $self->{'_opts'}{'sent_to_root'} = 0;
        if ( !length $self->{'_opts'}{'username'} || $self->{'_opts'}{'username'} eq 'root' || ( $self->{'_opts'}{'to'} && $self->{'_opts'}{'to'} eq 'root' ) ) {
            $self->{'_opts'}{'sent_to_root'} = 1;
        }
    }
    if ( !length $self->{'_opts'}{'domain'} ) {
        require Cpanel::AcctUtils::Domain;
        require Cpanel::Hostname;
        my $cpuser = ( $ENV{'TEAM_USER'} && $self->{'_opts'}{'username'} =~ /\@/ ) ? $ENV{'TEAM_OWNER'} : $self->{'_opts'}{'username'};
        $self->{'_opts'}{'domain'} = ( !length $self->{'_opts'}{'username'} || $self->{'_opts'}{'username'} eq 'root' ) ? scalar Cpanel::Hostname::gethostname() : scalar Cpanel::AcctUtils::Domain::getdomain($cpuser);
    }
    if ( !length $self->{'_opts'}{'host_server'} ) {
        require Cpanel::Hostname;
        $self->{'_opts'}{'host_server'} = Cpanel::Hostname::gethostname();
    }

    if ( length $self->{'_opts'}{'to'} ) {

        if ( $self->{'_opts'}{'to'} eq 'root' ) {

            # Cpanel::iContact will ONLY send a message to root if to has no length..
            delete $self->{'_opts'}{'to'};
        }
        else {
            require Cpanel::Locale::Utils::User;
            $self->{'_locale'} = Cpanel::Locale::Utils::User::get_user_locale( $self->{'_opts'}{'username'} );
        }
    }

    bless $self, $class;

    # TODO: Always skip sending and
    # wait for the send method to be called instead

    $self->send() unless $opts{'skip_send'};

    return $self;
}

sub send {
    my ($self) = @_;

    return unless -e '/etc/.whostmgrft';    # We don't want to send email messages until root's email is setup.

    # provides a blocking send, even if $opts{'skip_send'} is set and $self->send() is called later
    if ( $self->{'_opts'}->{'block_on_send'} ) {
        _do_in_foreground(
            sub {
                $self->_todo_inside_daemon();
            }
        );
    }

    # provides expected, default asynchronous sending when $opts{'skip_send'} is not set (original/common case)
    else {
        $self->{'_icontact_pid'} = _do_in_daemon(
            sub {
                $self->_todo_inside_daemon();
            }
        );
    }
    return 1;
}

sub pid {
    my ($self) = @_;

    return $self->{'_icontact_pid'};
}

sub body_format {
    my ($self) = @_;

    return $self->{'_body_format'};
}

sub importance_description {
    my ($self) = @_;

    require Cpanel::Locale;
    require Cpanel::iContact::EventImportance;
    my $importance_number = $self->importance();
    my $locale            = ( ref $self->{'_locale'} ? $self->{'_locale'} : Cpanel::Locale->get_handle( $self->{'_locale'} ) ) || Cpanel::Locale->get_handle();
    my %names             = (
        $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Disabled'} => $locale->maketext('Disabled'),
        $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Low'}      => $locale->maketext('Low'),
        $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Medium'}   => $locale->maketext('Medium'),
        $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'High'}     => $locale->maketext('High'),
    );
    return $names{$importance_number} || $names{0};
}

sub importance {
    my ($self) = @_;

    require Cpanel::iContact::EventImportance;
    my $importance = Cpanel::iContact::EventImportance->new();
    return $importance->get_event_importance(
        $self->_APPLICATION(),
        $self->_NAME(),
    );
}

sub render_template_include_as_text {
    my ( $self, %opts ) = @_;

    my $type = $opts{'type'};

    my $rendered = $self->render_template_include(%opts);

    if ( !length $rendered ) {
        my $path = $self->_RELATIVE_TEMPLATE_INCLUDE_PATH( $opts{'template'}, $opts{'type'} );
        die Cpanel::Exception->create_raw("render_template_include for “$path” failed for an unknown reason without generating an exception.");
    }

    return $rendered if $type eq 'text';

    return $self->_convert_html_to_text($rendered);
}

sub render_template_include {
    my ( $self, %opts ) = @_;

    my $template = $opts{'template'};
    my $type     = $opts{'type'};

    local $self->{'_locale'} = $opts{'locale'} || $self->_get_language_tag();

    $self->_make_required_template_modules_available();

    return $self->_get_parsed_template( $self->_RELATIVE_TEMPLATE_INCLUDE_PATH( $template, $type ), $type );
}

sub render_template_include_as_im {
    my ($self) = @_;

    $self->_make_required_template_modules_available();
    return $self->_get_im_message();
}

sub assemble_whm_url {
    my ( $self, $script_path ) = @_;
    return $self->_assemble_ui_url( 'whostmgrs', $script_path );
}

sub assemble_cpanel_url {
    my ( $self, $script_path ) = @_;
    return $self->_assemble_ui_url( 'cpanels', $script_path );
}

sub assemble_webmail_url {
    my ( $self, $script_path ) = @_;

    return $self->_assemble_ui_url( 'webmails', $script_path );
}

my %service_subdomains_map = (
    'whostmgrs' => 'whm',
    'cpanels'   => 'cpanel',
    'webmails'  => 'webmail',
);

# in v64, we use the best ssl on the users domain if there is one that
# will pass our checks
my %_url_authority_cache;

sub __clear_url_authority_cache {    # for testing
    %_url_authority_cache = ();
    return;
}

sub _assemble_ui_url {
    my ( $self, $service, $script_path ) = @_;

    if ( !$service_subdomains_map{$service} ) {
        die "Implementer error: _assemble_ui_url does not know how to handle the service “$service”.";
    }

    my $domain_key    = $self->{'_opts'}{'domain'} || '';
    my $url_authority = $_url_authority_cache{$service}{$domain_key};

    if ( !$url_authority ) {

        require Cpanel::SSL::Domain;
        require Cpanel::Config::LoadCpConf;
        require Cpanel::Domain::Local;

        if ( $self->{'_opts'}{'domain'} && Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'proxysubdomains'} ) {
            my ( $ssl_domain_info_status, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $service_subdomains_map{$service} . '.' . $self->{'_opts'}{'domain'}, { 'service' => 'cpanel' } );
            if ( $ssl_domain_info_status && $ssl_domain_info->{'ssldomain'} && index( $ssl_domain_info->{'cert_match_method'}, 'exact' ) == 0 && Cpanel::Domain::Local::domain_or_ip_is_on_local_server( $ssl_domain_info->{'ssldomain'} ) ) {
                $url_authority = $ssl_domain_info->{'ssldomain'};
            }
        }

        if ( !$url_authority ) {
            require Cpanel::Services::Ports;
            my ( $ssl_domain_info_status, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $self->{'_opts'}{'domain'} || Cpanel::Hostname::gethostname(), { 'service' => 'cpanel' } );
            if ( $ssl_domain_info_status && $ssl_domain_info->{'ssldomain'} && Cpanel::Domain::Local::domain_or_ip_is_on_local_server( $ssl_domain_info->{'ssldomain'} ) ) {
                $url_authority = $ssl_domain_info->{'ssldomain'} . ':' . $Cpanel::Services::Ports::SERVICE{$service};
            }
        }

        if ( !$url_authority ) {
            $url_authority = Cpanel::Hostname::gethostname() . ':' . $Cpanel::Services::Ports::SERVICE{$service};
        }

        $_url_authority_cache{$service}{$domain_key} = $url_authority;
    }

    return 'https://' . $url_authority . '/' . $script_path;
}

#----------------------------------------------------------------------

sub _de_stub_module {
    my ( $self, $module ) = @_;

    my $path = $module;
    $path =~ s<::></>g;
    $path .= '.pm';

    if ( $INC{$path} && $INC{$path} !~ m<\Q$path\E\z> ) {
        delete $INC{$path};
        Cpanel::LoadModule::load_perl_module($module);
        die "De-stubbing failed! ($INC{$path})" if $INC{$path} !~ m<\Q$path\E\z>;
    }

    return;
}

sub _todo_inside_daemon {
    my ($self) = @_;

    require Cpanel::iContact;

    # Avoid waiting on an integrity check when we just want to send a message
    local $Cpanel::SQLite::AutoRebuildBase::SKIP_INTEGRITY_CHECK = 1;
    $self->_make_required_template_modules_available();
    my $html_body  = $self->{'_body_format'} eq 'html' ? $self->_get_html_body() : undef;
    my $text_body  = $self->_get_text_body();
    my $im_message = $self->_get_im_message();

    my %icontact_opts = (
        application => $self->_APPLICATION(),
        event_name  => $self->_NAME(),
        $self->_icontact_args(),
    );

    $icontact_opts{'attach_files'} = Cpanel::iContact::normalize_attach_files( $icontact_opts{'attach_files'} );

    if ($html_body) {
        $icontact_opts{'message'}      = $html_body;
        $icontact_opts{'content-type'} = 'text/html; charset=utf8';

        if ($im_message) {

            #For ICQ
            $icontact_opts{'im_message'} = $im_message;
            $icontact_opts{'im_subject'} = $self->_get_im_subject();
        }

        if ($text_body) {

            #If we set plaintext_message for IM it will also set the default text body to it, so we have to keep them separate
            $icontact_opts{'plaintext_message'} = $text_body;
        }
    }
    else {
        $icontact_opts{'message'}      = $text_body;
        $icontact_opts{'content-type'} = 'text/plain; charset=utf8';
    }

    return Cpanel::iContact::icontact(
        subject      => scalar $self->_get_subject(),
        html_related => $self->{'_html_related'},
        x_headers    => {
            'iContact_locale' => scalar( $self->locale()->get_language_tag() ),
        },
        %icontact_opts,
    );
}

sub _make_required_template_modules_available {
    my ($self) = @_;

    #We have modules (e.g., Cpanel::TailWatch::Utils::Stubs) that stub out
    #these modules which Template Toolkit needs. That stubbing breaks T/T,
    #so let's have T/T reload the module.
    $self->_de_stub_module($_) for (@POTENTIALLY_STUBBED_MODULES);

    #NOTE: We do not load Cpanel::Template here because we do not want
    #to expose the same functionality that we extend to cPanel's internally
    #written templates (e.g., the WHM templates)

    require Template;
    require Template::Plugins;

    return 1;
}

sub _RELATIVE_TEMPLATE_INCLUDE_PATH {
    my ( $self, $template, $type ) = @_;

    my $name        = $self->_NAME();
    my $application = $self->_APPLICATION();

    return "$application/includes/$name.$template.$type.tmpl";
}

sub _RELATIVE_TEMPLATE_PATH {
    my ( $self, $type ) = @_;

    my $name        = $self->_NAME();
    my $application = $self->_APPLICATION();

    return "$application/$name.$type.tmpl";
}

sub _NAME {
    my ($self) = @_;

    my $name = ref $self;
    $name =~ s<.*::><> or die "Invalid package name: $name";

    return $name;
}

sub _APPLICATION {
    my ($self) = @_;

    my $class = ref $self;
    $class =~ m<.*::(.+)::> or die "Invalid package name: $class";

    return $1;
}

sub _verify_required_args {
    my ( $class, %opts ) = @_;

    my @missing = grep { !exists $opts{$_} } $class->_required_args();

    if (@missing) {
        die "$class: Missing the following args: @missing";
    }

    return 1;
}

sub _load_and_parse_template {
    my ( $self, %OPTS ) = @_;

    my $relative_path = $OPTS{'relative_path'};
    my $template_root = $OPTS{'template_root'};
    my $type          = $OPTS{'type'};
    my $locale        = $OPTS{'locale'};

    my $template_path = "$template_root/$relative_path";

    return undef if !-e $template_path;

    #----------------------------------------------------------------------
    #XXX SECURITY: As with anything where we expose Cpanel::Locale,
    #these templates are NOT safe to run as non-root.
    #
    #That's not important now since only root can edit the templates, but
    #when/if we delegate control over templates to non-root, we'll want
    #to exercise extra caution.
    #----------------------------------------------------------------------

    #TODO: Should we disable plugin loads? For non-root, at least?
    #cf. http://template-toolkit.org/docs/manual/Config.html#section_PLUGINS
    #local $Template::Plugins::PLUGIN_BASE = q<>;

    #XXX UGLY HACK!!!
    #Template::Plugins always does a require() on the template module, even if
    #that module is already loaded. require() for a module that doesn't have
    #its own file will barf, though, so we have to trick Perl into thinking
    #that we loaded this file from disk.
    require Template::Plugin;
    local $INC{'Cpanel/iContact/Class/Plugin/CPANEL.pm'} = __FILE__;

    my $tt_obj = Template->new(
        ABSOLUTE     => 0,
        RELATIVE     => 0,
        INCLUDE_PATH => $template_root,
        TRIM         => 1,
        PRE_CHOMP    => 0,
        POST_CHOMP   => 1,

        # Don't use the compiled templates if the compiled directory doesn't exist (if we're not root we can't recreate them)
        -d $Cpanel::ConfigFiles::TEMPLATE_COMPILE_DIR ? ( COMPILE_DIR => $Cpanel::ConfigFiles::TEMPLATE_COMPILE_DIR, ) : ( COMPILE_EXT => undef, ),
        LOAD_PLUGINS => [
            Template::Plugins->new( { PLUGINS => { CPANEL => __PACKAGE__ . '::Plugin::CPANEL' } } ),
        ],
    );

    #Have template toolkit use the user’s locale.
    my $template_loc_obj = $self->_find_or_return_locale_handle_from_input( $locale || $self->{'_locale'} );

    my @extra_CPANEL_plugin_args = (
        template_root   => $template_root,
        locale_obj      => $template_loc_obj,
        icontact_object => $self,
    );
    my ( $locale_context, @html_related );
    if ( $type eq 'html' ) {
        push @extra_CPANEL_plugin_args, ( html_related => \@html_related );
        $self->{'_html_related'} = \@html_related;
        $locale_context = 'html';
    }
    else {
        $locale_context = 'plain';
    }

    $tt_obj->context()->stash()->set(
        CPANEL => $tt_obj->context()->plugin( 'CPANEL', \@extra_CPANEL_plugin_args ),
    );

    my $output;
    my $ok = do {

        #Ugh. Setting the context on one C::L object sets it for subsequent
        #return values of C::L->get_handle(). Yuck, yuck. So, be sure that we
        #return *this* object’s context to its original state when we’re done.
        #
        my $original_locale_context = $template_loc_obj->get_context();
        $template_loc_obj->set_context($locale_context);
        my $put_back_locale_context = Cpanel::Finally->new(
            sub {
                $template_loc_obj->set_context($original_locale_context);
            }
        );

        # The iContact template arguments are going to be the same reguardless of which
        # template we are going to render.  We want to process these only once per
        # notification as its wasteful and we always want to make sure the
        # subject and body agree.
        #
        # Previously we re-processed the arguments 4 or more times for each part
        # of the notification including:
        #
        # HTML body
        # TEXT body
        # TEXT subject
        # IM subject
        # IM body
        $self->{'_processed_template_args'} ||= { $self->_template_args() };

        $tt_obj->process(
            $relative_path,    # This used to send in the contents of the template
                               # however that approch made this slower because
                               # Template::Toolkit could not leverage the COMPILE_DIR
                               # option
            {
                NOTICE => $self->{'_processed_template_args'},
            },
            \$output,
        );
    };

    if ( !$ok ) {
        my $err = $tt_obj->error();
        require Cpanel::ScalarUtil;
        if ( Cpanel::ScalarUtil::blessed($err) && $err->isa('Template::Exception') ) {
            die Cpanel::Exception::create( 'Template', [ error => $err, template_path => $template_path ] );
        }

        die $err;
    }

    require Cpanel::LoadFile;

    #Convert what the plugin gave us into what
    #Cpanel::iContact::icontact()'s "html_related" parameter expects.
    for my $html_rel (@html_related) {
        my $full_path = "$template_root/$html_rel->{'path'}";

        #NOTE: We can't just pass "content" as a filehandle because
        #iContact::icontact() will read from "content" twice.
        $html_rel->{'content'} = Cpanel::LoadFile::load_r($full_path);

        if ( !$html_rel->{'content_type'} ) {
            require Cpanel::FileType;
            $html_rel->{'content_type'} = Cpanel::FileType::determine_mime_type($full_path) || 'application/octet-stream';
        }

        my $filename = $html_rel->{'path'};
        $filename =~ s<.*/><>;
        $html_rel->{'name'} = $filename;
    }

    return $output;
}

sub _get_subject {
    my ( $self, $opts ) = @_;

    #if we are retrieving a subject for an im we need it in english due to breakage in Net::OSCAR
    my $locale_obj = $self->_find_or_return_locale_handle_from_input( $opts->{'locale'} || $self->{'_locale'} );
    my $locale     = $locale_obj->get_language_tag();

    return $self->{'_text_subject'}{$locale} if $self->{'_text_subject'}{$locale};

    my $subj = $self->_get_parsed_template( $self->_RELATIVE_TEMPLATE_PATH('subject'), 'subject', $locale_obj );

    Cpanel::StringFunc::Trim::ws_trim( \$subj );

    require Cpanel::Validate::Whitespace;
    Cpanel::Validate::Whitespace::ascii_only_space_or_die($subj);

    return ( $self->{'_text_subject'}{$locale} ||= $subj );
}

#Returns two things: the template, and the template root where it was found.
#...or, returns nothing if there was no template of the given type to be found.
#
#NOTE: This will NOT check for a default "text" template; by definition, the
#default "text" output is just HTML::FormatText on the HTML output.
#
sub _get_parsed_template {
    my ( $self, $relative_path, $type, $locale ) = @_;

    my $parsed;
    try {
        $parsed = $self->_load_and_parse_template( 'relative_path' => $relative_path, 'template_root' => $_CUSTOM_TEMPLATES_DIR, 'type' => $type, 'locale' => $locale );
    }
    catch {
        require Cpanel::ScalarUtil;
        my $err   = $_;
        my $class = Cpanel::ScalarUtil::blessed($err);
        if ( $class && $err->isa('Cpanel::Exception::Template') ) {
            my $star_line = '*' x 80;
            Cpanel::Debug::log_warn( "\n$star_line\nError while parsing the custom “$type” template\n$star_line\n" . $err->to_string() . "\n" . $star_line );
        }
        else {
            die $err;
        }
    };

    return $parsed if defined $parsed;
    return $self->_load_and_parse_template( 'relative_path' => $relative_path, 'template_root' => $_DEFAULT_TEMPLATES_DIR, 'type' => $type, 'locale' => $locale );
}

sub _get_html_body {
    my ( $self, $locale ) = @_;

    $locale ||= $self->{'_locale'} || $self->_get_language_tag();

    return ( $self->{'_html_body'}{$locale} ||= $self->_get_parsed_template( $self->_RELATIVE_TEMPLATE_PATH('html'), 'html', $locale ) );
}

sub _get_text_body {
    my ( $self, $locale ) = @_;

    $locale ||= $self->{'_locale'} || $self->_get_language_tag();

    return $self->{'_text_body'}{$locale} if $self->{'_text_body'}{$locale};

    $self->{'_text_body'}{$locale} ||= $self->_get_parsed_template( $self->_RELATIVE_TEMPLATE_PATH('text'), 'text', $locale );

    return $self->{'_text_body'}{$locale} if $self->{'_text_body'}{$locale};

    my $html_body = $self->_get_html_body($locale);
    if ( !$html_body ) {
        require Carp;
        Carp::croak("Huh?? Neither HTML nor text body?!? Something is wrong!");
    }

    return ( $self->{'_text_body'}{$locale} ||= $self->_convert_html_to_text($html_body) );
}

sub _get_im_message {
    my ($self) = @_;

    return _format_for_im( $self->{'_text_body'}{'en'} ) if $self->{'_text_body'}{'en'};

    my $html_body = $self->_get_html_body('en');
    if ( !$html_body ) {
        require Carp;
        Carp::croak("Huh?? No HTML body?!? Something is wrong!");
    }

    $self->{'_text_body'}{'en'} = $self->_convert_html_to_text($html_body);

    return _format_for_im( $self->{'_text_body'}{'en'} );
}

sub _get_im_subject {
    my ($self) = @_;

    my $subject = $self->_get_subject( { 'locale' => 'en' } );
    return _format_for_im($subject);
}

sub _get_language_tag {
    my ($self) = @_;

    if ( $self->{'_locale_obj'} ) {
        return $self->{'_locale_obj'}->get_language_tag();
    }
    require Cpanel::Locale;
    return Cpanel::Locale->get_handle()->get_language_tag();
}

sub _convert_html_to_text {
    my ( $self, $html_body ) = @_;

    require HTML::FormatText;
    require Cpanel::UTF8::Strict;

    my $text_body = HTML::FormatText->format_string(

        #Without this we get warnings from HTML::Parser like:
        #
        #Parsing of undecoded UTF-8 will give garbage when decoding entities
        #
        Cpanel::UTF8::Strict::decode($html_body),

        leftmargin => 0,

        #HTML::FormatText doesn't seem to expose a way to
        #suppress line wrapping, so set this to something
        #"ridiculously" high to achieve the effect:
        rightmargin => $FAUX_LINE_WRAP_SUPPRESSION,
    );

    # HTML::FormatText::end is going to add an extra unwanted newline
    chomp($text_body);

    #Without this we get "wide character in print" warnings. (Yeesh!)
    utf8::encode($text_body);
    return $text_body;
}

sub _format_for_im {
    my ($string) = @_;

    #convert curly quotes
    $string =~ s/“/"/ig;
    $string =~ s/”/"/ig;
    $string =~ s/’/'/ig;
    $string =~ s/‘/'/ig;

    #convert »
    $string =~ s/[»]+/>>/g;

    #convert any non-ascii character to '?'
    $string =~ s/[^\x00-\x7f]+?/?/g;

    return $string;
}

# $input can be a
#   Cpanel::Locale object
#   A locale name ie 'en'
#
# This will find or create the
# Cpanel::Locale object and return it
sub _find_or_return_locale_handle_from_input {
    my ( $self, $locale_input ) = @_;
    if ( try { $locale_input->isa('Cpanel::Locale') } ) {
        return $locale_input;
    }
    require Cpanel::Locale;
    return Cpanel::Locale->get_handle($locale_input);
}

package Cpanel::iContact::Class::Plugin::CPANEL;

use parent -norequire, 'Template::Plugin';

use Try::Tiny;

sub new {
    my ( $class, $context, %opts ) = @_;

    require Template::Plugin;

    my $self = {
        _locale_obj      => $opts{'locale_obj'},
        _template_root   => $opts{'template_root'},
        _html_related    => $opts{'html_related'},
        _icontact_object => $opts{'icontact_object'},
    };

    return bless $self, $class;
}

# Convert a raw text message so it can
# be displayed inline in an HTML message
sub format_text_as_html {
    my ( $plugin, $text ) = @_;

    require Cpanel::Output::Formatted::HTMLEmail;
    my $html       = q{};
    my $output     = open my ($html_fh), '>', \$html or die "cannot create scalar file handle for text formatter";
    my $output_obj = Cpanel::Output::Formatted::HTMLEmail->new( 'filehandle' => $html_fh );
    foreach my $line ( split( m{\n}, $text ) ) {
        $output_obj->output_highlighted_message($line);
    }
    return $html;
}

sub now { return time }

sub iso2unix {
    my $self = shift;
    require Cpanel::Time::ISO;
    goto \&Cpanel::Time::ISO::iso2unix;
}

sub iso_time {
    my $self = shift;
    Cpanel::Debug::log_deprecated('This function will be removed, please use locale datetime');
    require Cpanel::Time::ISO;
    goto \&Cpanel::Time::ISO::unix2iso_time;
}

sub iso_date {
    my $self = shift;
    Cpanel::Debug::log_deprecated('This function will be removed, please use locale datetime');
    require Cpanel::Time::ISO;
    goto \&Cpanel::Time::ISO::unix2iso_date;
}

sub iso_datetime {
    my $self = shift;
    Cpanel::Debug::log_deprecated('This function will be removed, please use locale datetime');
    require Cpanel::Time::ISO;
    goto \&Cpanel::Time::ISO::unix2iso;
}

sub locale {
    my ($self) = @_;

    return $self->{'_locale_obj'};
}

sub split_time_dhms {
    my ( $plugin, $seconds ) = @_;
    require Cpanel::Time::Split;
    return [ Cpanel::Time::Split::epoch_to_dhms($seconds) ];
}

# Based on module_description()
sub notification_system_name {
    my ($self) = @_;

    require Cpanel::iContact;
    $self->{'_description_hash'} ||= { Cpanel::iContact::contact_descriptions( $self->locale() ) };

    my $app  = $self->{'_icontact_object'}->_APPLICATION();
    my $name = $self->{'_icontact_object'}->_NAME();

    #If app::name exists, return that since it's the most specific instance
    return "${app}::${name}" if ( $self->{'_description_hash'}->{"${app}::${name}"}{'display_name'} );

    #Otherwise just return app if it exists
    return $app if ( $self->{'_description_hash'}->{$app}{'display_name'} );

    #in case none of these are right, die
    warn "Unable to find notification with system name: ${app}::${name}";

    return 'Application';    # Uncategorized Notifications
}

sub module_event_importance_description {
    my ($self) = @_;
    return $self->{'_icontact_object'}->importance_description();
}

sub notification_priority {
    my ($self) = @_;
    return $self->{'_icontact_object'}->importance();
}

sub module_namespace {
    my ($self) = @_;

    return join( '::', $self->{'_icontact_object'}->_APPLICATION(), $self->{'_icontact_object'}->_NAME() );
}

sub module_description {
    my ($self) = @_;

    require Cpanel::iContact;
    $self->{'_description_hash'} ||= { Cpanel::iContact::contact_descriptions( $self->locale() ) };

    my $app  = $self->{'_icontact_object'}->_APPLICATION();
    my $name = $self->{'_icontact_object'}->_NAME();

    return $self->{'_description_hash'}->{"${app}::${name}"}{'display_name'} if ( $self->{'_description_hash'}->{"${app}::${name}"} );
    return $self->{'_description_hash'}->{$app}{'display_name'}              if ( $self->{'_description_hash'}->{$app} );
    return "${app}::${name}";
}

sub assemble_whm_url {
    my ( $self, $whm_script_path ) = @_;
    return $self->{'_icontact_object'}->assemble_whm_url($whm_script_path);
}

sub webmail_contact_info_url {
    my ( $self, $user ) = @_;
    return $self->{'_icontact_object'}->assemble_webmail_url( $self->_contact_info_url( $user, 'webmaild' ) );
}

sub cpanel_contact_info_url {
    my ( $self, $user ) = @_;
    return $self->{'_icontact_object'}->assemble_cpanel_url( $self->_contact_info_url( $user, 'cpaneld' ) );
}

sub get_icon {
    my ( $self, $icon_name ) = @_;

    require Cpanel::iContact::Icons;
    return Cpanel::iContact::Icons::get_icon($icon_name) || (

        #Leaving this un-HTML-ified … it should be rare anyway.
        '[' . $self->locale()->maketext( 'Missing icon “[_1]”', $icon_name ) . ']'
    );
}

sub _contact_info_url {
    my ( $self, $user, $service ) = @_;
    if ( $service eq 'cpaneld' ) {
        return '?goto_app=ContactInfo_Change';
    }
    my $url = '';
    try {
        require Cpanel::Themes;
        $url = Cpanel::Themes::get_user_link_for_app( $user, 'ContactInfo_Change', $service );
    };
    return $url;
}

#named args:
#
#   path - required, relative to template root
#
#   content_type - optional; will try to guess if not provided
#       defaults to application/octet-stream if we can't guess,
#       which is likely if we're given something that's not an image.
#
#The return value is an auto-generated Content-Id that you can use to refer
#to this item in your HTML document. This Content-Id is safe to include
#without URI encoding.
#
sub add_html_related {
    my ( $plugin, $opts_hr ) = @_;

    require Cpanel::Hash;
    require Cpanel::Autodie;

    my $html_related_ar = $plugin->{'_html_related'};

    if ( !$html_related_ar ) {
        die 'This method is not available for this template!';
    }

    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes( $opts_hr->{'path'} );

    my $filepath = "$plugin->{'_template_root'}/$opts_hr->{'path'}";
    my ( $size, $mtime ) = ( Cpanel::Autodie::stat($filepath) )[ 7, 9 ];

    my $md5 = Cpanel::Hash::get_fastest_hash("$size-$mtime-$filepath");

    $opts_hr->{'content_id'} = "auto_cid_$md5";

    push @$html_related_ar, $opts_hr;

    return $opts_hr->{'content_id'};
}

1;
