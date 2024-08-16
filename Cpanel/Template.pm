package Cpanel::Template;

# cpanel - Cpanel/Template.pm                        Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Template::Shared ();

BEGIN {
    require Template;
    require Template::Context;
    require Template::Filters;
    require Template::Iterator;
    require Template::Plugin;
    require Template::Plugins;
    require Template::Stash;
    require Cpanel::Template::Plugin::VarCache;    # PPI USE OK -- hide from parser since template plugin namespaces are funny.

    if ( index( $0, 'whostmgr' ) > -1 ) {
        require Cpanel::Template::Plugin::Encoder;    # PPI USE OK -- hide from parser since template plugin namespaces are funny.
    }
    BEGIN { ${^WARNING_BITS} = ''; }                  ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings

####
#### The below avoids importing File:: which was 15% of cPanel's startup time
####
    {
        *Template::Document::write_perl_file   = *write_perl_file;
        *Template::Provider::_template_content = *Cpanel::Template::Shared::_template_content;
        *Template::Provider::_load_compiled    = *Cpanel::Template::Shared::_load_compiled;
    }
####
#### The below adds additional sanity checking for when the compiled template is up-to-date
####
    {
        *Template::Provider::_compiled_is_current = *Cpanel::Template::Shared::_compiled_is_current;
    }
####
#### This block is really just
####
#### package Template::Stash; use constant 'undefined' => '';
####
#### in order to make Template::Stash::undefined as cheap as
#### possible since it is called so frequently in our codebase
#### to do nothing.
####
#### We have to do the constant setup manually because
#### the prototype does not match and we cannot turn off the
#### the warning in the constant module.  We have to turn off
#### the warning because it would pollute in the error log
#### on every template toolkit execution.
####
    {
        BEGIN { ${^WARNING_BITS} = ''; }        ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings
        my $scalar = '';
        Internals::SvREADONLY( $scalar, 1 );    # DANGER: see above for why we are stuck with this
        local $Cpanel::Template::{_dummy} = \$scalar;
        *Template::Stash::undefined = \&{"_dummy"};
    }

}

use strict;

require base;    #needed for Template loading
use Cpanel::JSON            ();
use Cpanel::ConfigFiles     ();
use Cpanel::Debug           ();
use Cpanel::LoadModule      ();
use Cpanel::Template::Files ();
use Template::Constants     ();
use Template::Stash::XS     ();

use Cpanel::Template::Plugin::JSON ();    # PPI USE OK -- hide from parser since template plugin namespaces are funny.
use Cpanel::Encoder::Tiny          ();    ## for css_encode_str ('FILTER css');
use Cpanel::Encoder::URI           ();

our $VERSION = '2.1';

our $SHARED_TEMPLATES_DIR        = '/usr/local/cpanel/base/templates';
our $LAST_TEMPLATE_USED_COMPILED = 0;

our $COMPILE_DIR;
*COMPILE_DIR = \$Cpanel::ConfigFiles::TEMPLATE_COMPILE_DIR;

*get_template_file          = *Cpanel::Template::Files::get_service_template_file;
*get_service_template_file  = *Cpanel::Template::Files::get_service_template_file;
*get_branding_template_file = *Cpanel::Template::Files::get_branding_template_file;

my %singleton_stash;
END { undef %singleton_stash }

my $read_only_templates = 0;
our $next_compiled_filename_call_allowed = 0;

sub _init_readonly_templates {
    return if $read_only_templates || $> == 0;
    $read_only_templates = 1;

    # We make Template::Provider::_compiled_filename return undef when called from Template::Provider::_fetch if it isn't called right after a true Template::Provider::_compiled_is_current
    # This way we don't try to write out a template ever.  Only read it in.
    BEGIN { ${^WARNING_BITS} = ''; }    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings
    my $orig_template_provider__compile = \&Template::Provider::_compile;
    *Template::Provider::_compile = sub {
        my ( $self, $data, $compfile ) = @_;
        return $orig_template_provider__compile->( $self, $data );
    };

    return;
}

my $_var_cache;

sub get_tt_obj {
    my ( $class, $options_hr ) = @_;

    my @args_map;
    if ( $options_hr->{'INCLUDE_PATH'} ) {
        @args_map = 'INCLUDE_PATH;' . join( ',', @{ $options_hr->{'INCLUDE_PATH'} } );
    }
    push @args_map,
      (
        map { "$_;$options_hr->{$_}" } grep {

            # Exclude varibles that will not change during
            # the execution of the process
                 $_ ne 'PLUGIN_BASE'
              && $_ ne 'INCLUDE_PATH'
              && $_ ne 'FILTERS'
              && $_ ne 'RELATIVE'
              && $_ ne 'POST_CHOMP'
              && $_ ne 'PRE_CHOMP'
              && $_ ne 'STAT_TTL'
              && $_ ne 'ABSOLUTE'
        } keys %{$options_hr}
      );

    # cp_security_token is special because we store it in the object
    # on load in BaseDefault.pm in order to avoid having to make it
    # a coderef (slow) that fetches it
    push @args_map, "ENV_cp_security_token;" . ( $ENV{'cp_security_token'} || '' );

    my $args_sig = scalar @args_map > 1 ? join( ',', sort @args_map ) : ( $args_map[0] || 'no_args' );

    $options_hr->{'NAMESPACE'}->{'varcache'} = ( $_var_cache ||= cVC->new() );    # PPI NO PARSE - loaded by Cpanel/Template/   Plugin/VarCache.pm

    return (
        ( exists $singleton_stash{$class}{$args_sig} && ++$singleton_stash{$class}{$args_sig}->{'_singleton_reused'} )
        ? $singleton_stash{$class}{$args_sig}
        : ( $singleton_stash{$class}{$args_sig} = Template->new($options_hr) )
    );

}

my ($locale);

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
        $tmpfile =~ tr{/}{}s;                                                                # collapse //s to /
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

####
#### The above avoids importing File:: which was 15% of cPanel's startup time
####

#NOTE: $input_hr's "template_file" can be a scalar ref if you want to use a
#template that's in memory rather than one on disk.
#
my $_filters;

sub process_template {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $service, $input_hr, $options_hr ) = @_;
    $options_hr ||= {};    # Optional

    #if void context and no 'print' specified, then print
    #if 'print' is true, print
    #otherwise, no print
    my $void_context = !defined wantarray();
    my $is_root      = $> == 0                              ? 1 : 0;
    my $input_is_hr  = $input_hr && ref $input_hr eq 'HASH' ? 1 : 0;

    # Verify input
    if ( !$service ) {
        if ( $input_hr->{'print'} ) {
            print 'No service specified';
            return;
        }
        return wantarray ? ( 0, 'No service specified' ) : 0;
    }
    elsif ( !$input_is_hr ) {
        if ( $input_hr->{'print'} ) {
            print 'No template data provided';
            return;
        }
        return wantarray ? ( 0, 'No template data provided' ) : 0;
    }
    elsif ( $input_is_hr && $input_hr->{'compile_only'} ) {
        delete @{$input_hr}{ 'print', 'skip_template_cache' };
    }

    # Make sure CPSESSIONTHEME does not have a path traversal strings.
    # It is an added security check to not let anyone use the CPSESSIONTHEME
    # as a medium to redirect to a different location external to cpanel.
    # Example: ../../../themename.
    if ( $ENV{'CPSESSIONTHEME'} && index( $ENV{'CPSESSIONTHEME'}, '/' ) > -1 ) {
        Cpanel::Debug::log_warn("The 'CPSESSIONTHEME' ENV variable has invalid characters.");
        return;
    }

    my $print_yn = ( $void_context && !exists $input_hr->{'print'} ) || $input_hr->{'print'};

    my $template_file;
    if ( exists $input_hr->{'template_file'} ) {
        $template_file = $input_hr->{'template_file'};

        if ( !$template_file ) {
            if ( $input_hr->{'print'} ) {
                print 'Template file not defined.';
                return;
            }
            return wantarray ? ( 0, "Template file not defined." ) : 0;
        }
        elsif ( index( $template_file, '/' ) != 0 ) {    #relative path
            $template_file =~ s{\.\./}{}g;
        }
        else {
            $template_file = $input_hr->{'template_file'};
        }
    }
    else {    #default template files for services
        my $error;
        if ( $options_hr->{'branding'} ) {
            ( $template_file, $error ) = Cpanel::Template::Files::get_branding_template_file( $service, $options_hr );
        }
        else {
            ( $template_file, $error ) = Cpanel::Template::Files::get_service_template_file( $service, $options_hr->{'skip_local'} );
        }
        if ( !$template_file ) {
            if ( $input_hr->{'print'} ) {
                print $error;
                return;
            }
            return wantarray ? ( 0, $error ) : 0;
        }
    }

    # Check for local versions of any included template files
    #
    #NB: Duplicated with:
    #   - Cpanel::ConfigFiles::Apache::vhost::render_vhost()
    #   - @Cpanel::ConfigFiles::Apache::local::possible_templates
    #
    foreach my $include ( keys %{ $input_hr->{'includes'} } ) {
        if ( !$options_hr->{'skip_local'} && -e $Cpanel::Template::Files::tmpl_dir . '/' . $service . '/' . $include . '.local' ) {
            $input_hr->{'includes'}{$include} = $service . '/' . $include . '.local';
        }
        elsif ( -e $Cpanel::Template::Files::tmpl_dir . '/' . $service . '/' . $include . '.default' ) {
            $input_hr->{'includes'}{$include} = $service . '/' . $include . '.default';
        }
        elsif ( -e $Cpanel::Template::Files::tmpl_source_dir . '/' . $service . '/' . $include . '.default' ) {
            $input_hr->{'includes'}{$include} = $Cpanel::Template::Files::tmpl_source_dir . '/' . $service . '/' . $include . '.default';
        }
    }

    ## Create Template object allowing absolute filenames, as well as
    ##   non-absolute paths (not starting with './') that are relative to the
    ##   given INCLUDE_PATH. Actual RELATIVES (i.e. './winston.html') are
    ##   disallowed per the below.
    $options_hr->{'ABSOLUTE'} = 1;

    #
    # Note: if you uncomment to turn on debug mode, you may
    # which to comment out the override of Template::Stash::undefined
    # above as well
    #
    #$options_hr->{'DEBUG'} = 'parser, provider';
    $options_hr->{'STAT_TTL'}    = 60;
    $options_hr->{'RELATIVE'}    = 0;
    $options_hr->{'PRE_CHOMP'}   = 0;
    $options_hr->{'POST_CHOMP'}  = 0;
    $options_hr->{'PLUGIN_BASE'} = 'Cpanel::Template::Plugin';
    $options_hr->{'FILTERS'}     = ( $_filters ||= { html => \&Cpanel::Encoder::Tiny::safe_html_encode_str, css => \&Cpanel::Encoder::Tiny::css_encode_str, 'uri' => \&Cpanel::Encoder::URI::uri_encode_str, 'json' => \&Cpanel::JSON::SafeDump } );

    ## 'TOLERANT' does not do what you expect; see Context.pm ~ L455; throws an
    ##   ERROR_FILE (i.e. dies), or two lines later throw the same ERROR_FILE;
    ##   the need for 'tolerance' is managed by the creation of CPDefault's &template_exists
    #$options_hr->{'TOLERANT'} = 1;

    my $include_path = delete $options_hr->{'include_path'} || '';

    if ( ref $include_path eq 'ARRAY' ) {
        $options_hr->{'INCLUDE_PATH'} = $include_path;
    }
    elsif ( $include_path ne q[] ) {
        $options_hr->{'INCLUDE_PATH'} = [$include_path];
    }
    else {
        $options_hr->{'INCLUDE_PATH'} = [];
    }

    foreach my $path ( @{ $options_hr->{'INCLUDE_PATH'} } ) {
        if ( index( $path, '/' ) != 0 ) {
            die("Cpanel::Template only permits absolute include paths (relative paths cannot be cached): “$path” must be an absolute path");
        }
    }

    # Set the right dir path for cpanel or webmail app
    my $app_dir;
    if ( $service eq 'whostmgr' ) {
        require Whostmgr::Theme;

        push @{ $options_hr->{'INCLUDE_PATH'} }, '/usr/local/cpanel/whostmgr/docroot/themes/' . Whostmgr::Theme::gettheme() . '/templates', '/usr/local/cpanel/whostmgr/docroot/templates', $SHARED_TEMPLATES_DIR,;

        #Security Policy can’t load any templates that have been
        #saved as root because write_perl_file() saves as 0600.
        #TODO: Remove this once the above (CPANEL-15585) is fixed.
        if ( !$is_root ) {
            $input_hr->{'skip_template_cache'} = 1;
        }
    }
    elsif ( $service eq 'cpanel' || $service eq 'webmail' ) {
        $app_dir = $service eq 'cpanel' ? 'frontend' : 'webmail';

        # $ENV{'USER'} gets set in Cpanel.pm::initcp()
        my $user = $ENV{'USER'} || $ENV{'REMOTE_USER'};
        my %themes;

        # Include path checks session theme, user theme, and default to the default cpanel theme.
        $themes{ $Cpanel::CPDATA{'RS'} }  = 1 if $Cpanel::CPDATA{'RS'}  && index( $Cpanel::CPDATA{'RS'},  '/' ) == -1;
        $themes{ $ENV{'CPSESSIONTHEME'} } = 1 if $ENV{'CPSESSIONTHEME'} && index( $ENV{'CPSESSIONTHEME'}, '/' ) == -1;

        unshift @{ $options_hr->{'INCLUDE_PATH'} }, ( map { "/usr/local/cpanel/base/$app_dir/" . $_ } keys %themes ), $SHARED_TEMPLATES_DIR;

        # If we are running as root, be sure not to generate the templates
        if ( !exists $input_hr->{'skip_template_cache'} && !exists $input_hr->{'compile_only'} ) {
            $input_hr->{'skip_template_cache'} = $is_root ? 1 : 0;
        }
    }
    elsif ( $service eq 'securitypolicy' ) {
        push @{ $options_hr->{'INCLUDE_PATH'} }, '/usr/local/cpanel/base/securitypolicy/',;
    }

    #only apache needs this, but just in case
    else {
        push @{ $options_hr->{'INCLUDE_PATH'} }, $Cpanel::Template::Files::tmpl_dir;
    }

    #Common shared location for template includes
    push @{ $options_hr->{'INCLUDE_PATH'} }, '/usr/local/cpanel/shared/templates';

    if ( !$input_hr->{'skip_template_cache'} ) {
        if ( -e $COMPILE_DIR ) {
            $options_hr->{'COMPILE_DIR'} = $COMPILE_DIR;
        }
        elsif ($is_root) {
            mkdir( $COMPILE_DIR, 0755 );
            $options_hr->{'COMPILE_DIR'} = $COMPILE_DIR;
        }
    }

    my $template;
    {
        BEGIN { ${^WARNING_BITS} = ''; }    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings
        local $INC{'File/Path.pm'} = __FILE__;
        local *File::Path::mkpath = sub {
            return 1 if substr( $_[0], 0, length $COMPILE_DIR ) eq $COMPILE_DIR;
            require Cpanel::SafeDir::MK;
            goto \&Cpanel::SafeDir::MK::safemkdir;
        };
        $template = __PACKAGE__->get_tt_obj($options_hr)
          || return wantarray ? ( undef, $Template::ERROR ) : ();
    }

    # case 59224: must happen after get_tt_obj
    _init_readonly_templates() if !$read_only_templates && !$is_root && $options_hr->{'COMPILE_DIR'};

    #default plugins
    my $context = $template->{SERVICE}->{CONTEXT};

    if ( $input_hr->{'compile_only'} ) {
        $context->template($template_file);
        return;
    }

    if ( index( $service, 'apache' ) > -1 || index( $service, 'vhost' ) > -1 ) {
        $context->plugin('Apache');    #This plugin just adds to the stash.

        # Create a list of all IPs in use for use in the proxy (cpanel|whm|webmail)
        # setup in the templates.
        my %seen;
        $input_hr->{'ips_in_use'} = [
            grep { !$seen{$_}++ } map {
                map { $_->{ip} }
                  @{ $_->{ips} }
            } @{ $input_hr->{vhosts} }
        ];

        # If the main ip isn't used in any vhosts (happens when there are no domains configured on the server)
        # then check and add it to the ips in use list, as we need that included in the virtualhost for the
        # subdomain proxies.
        foreach my $key (qw/main_ip main_ipv6/) {
            if ( $input_hr->{$key} and not $seen{ $input_hr->{$key} } ) {
                push @{ $input_hr->{'ips_in_use'} }, $input_hr->{$key};
            }
        }

        # copy the version string (eg: 2, 2_2, 2_4) into a variable accessible
        # within the template
        $input_hr->{'apache_target_version'} = $input_hr->{'_use_target_version'};    # if $service =~ m{apache}i;
    }
    elsif ( index( $service, 'dovecot' ) > -1 ) {

        # no plugins needed by default
    }
    elsif ( ref $context ) {
        $context->stash()->set( 'JSON', $context->plugin('JSON') );
        if ( $service eq 'cpanel' || $service eq 'webmail' || $service eq 'cpanel_injected' ) {
            $context->plugin('CPDefault');
            $context->stash()->set( 'ExpVar', $context->plugin('ExpVar') );
            $context->stash()->set( 'Api2',   $context->plugin('Api2') );
            $context->stash()->set( 'Api1',   $context->plugin('Api1') );

            if ( $service eq 'cpanel' ) {    # legacy compat
                $context->stash()->set( 'Api', $context->plugin('Api2') );
            }
        }
        elsif ( $service eq 'whostmgr' ) {
            $context->plugin('Whostmgr');
        }
        else {
            $context->plugin('BaseDefault');
        }
    }

    # Process template
    my @output_arg = $print_yn ? ( my $output_sr ) : ();
    my $output;

    return if !ref $template || ref $template eq 'HASH';    # global destruction issue

    if ($print_yn) {

        # true if using Cpanel::Template::Interactive

        my $success = $template->process( $template_file, $input_hr );
        $output = '';

        if ($success) {
            return ( $success, \$output );
        }
        else {
            print $template->error();
            return ( 0, \$output );
        }
    }
    else {
        my $success = $template->process( $template_file, $input_hr, \$output );

        if ($success) {
            return wantarray ? ( $success, \$output ) : \$output;
        }
        else {
            return wantarray ? ( undef, $template->error() ) : ();
        }
    }
}

sub getzonetemplate {

    Cpanel::Debug::log_panic("Cpanel::Template::getzonetemplate called instead of Cpanel::DnsUtils::Template::getzonetemplate");
    return;
}

sub globber {
    eval '*globber = sub { return glob shift; };';
    if ( !$@ ) {
        goto \&globber;
    }
}

1;
