package Cpanel::cPAddons::Obj;

# cpanel - Cpanel/cPAddons/Obj.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (TestingAndDebugging::RequireUseWarnings) -- existing cPAddons code is not warnings-safe

use Cpanel                            ();
use Cpanel::AdminBin::Call            ();
use Cpanel::cPAddons::Actions         ();
use Cpanel::cPAddons::Cache           ();
use Cpanel::cPAddons::Globals         ();
use Cpanel::cPAddons::Globals::Static ();
use Cpanel::cPAddons::License         ();
use Cpanel::cPAddons::Instances       ();
use Cpanel::cPAddons::Notices         ();
use Cpanel::cPAddons::Security        ();
use Cpanel::cPAddons::Transform       ();
use Cpanel::cPAddons::Util            ();
use Cpanel::DbUtils                   ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::Exception                 ();
use Cpanel::Binaries                  ();
use Cpanel::Hostname                  ();
use Cpanel::Locale                    ();
use Cpanel::LoadModule                ();
use Cpanel::PasswdStrength::Check     ();
use Cpanel::PwCache                   ();
use Cpanel::PwCache::Get              ();
use Cpanel::Rand                      ();
use Cpanel::SafeDir::RM               ();
use Cpanel::SafeDir::MK               ();
use Cpanel::Template                  ();

use Fcntl ();

# Specials
use Cpanel::Imports;
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

=head1 NAME

Cpanel::cPAddons::Obj

=head1 DESCRIPTION

In cPAddons, "obj" is the name for a very cluttered collection of system state and
HTML snippets that are both used internally and exposed to cPAddon modules for
possible custom use (including by third parties). As an initial step toward trying
to make this less unpleasant, the "obj" setup code has been moved into a standalone
module.

This module handles the creation of this object as well as the default actions
for install, uninstall, etc.

=head1 FUNCTIONS

=head2 create_obj( ... )

Instantiate $obj

=head3 Arguments

This function accepts a list of key/value pairs:

- err

- err_hr

- module_hr

- input_hr

- moderated

- safe_input_hr

- response

- mod

=head3 Returns

$obj - A Cpanel::cPAddons::Obj instance

=cut

sub create_obj {    ## no critic (Subroutines::ProhibitExcessComplexity) -- This is cPAddons legacy code that has already been improved somewhat but still fails the complexity test.
    my %args = @_;

    my (
        $err,
        $env_hr,
        $module_hr,
        $input_hr,
        $moderated,
        $safe_input_hr,
        $response,
        $mod,
      ) = @args{
        qw(
          err
          env_hr
          module_hr
          input_hr
          moderated
          safe_input_hr
          response
          mod
        )
      };

    my $info_hr = $module_hr->{meta} || {};

    my $obj = bless {}, __PACKAGE__;

    $obj->{'unix_time'}         = time;
    $obj->{'lang_obj'}          = locale();
    $obj->{'debug'}             = $input_hr && $input_hr->{'debug'}   ? 1 : 0;
    $obj->{'verbose'}           = $input_hr && $input_hr->{'verbose'} ? 1 : 0;
    $obj->{'force_text'}        = $Cpanel::cPAddons::Globals::force_text;
    $obj->{'force_text_length'} = length $Cpanel::cPAddons::Globals::force_text;

    # Notices section
    $obj->{'notices'} = Cpanel::cPAddons::Notices::singleton();

    # Domain related section
    my $domain_to_docroot_map = _get_domain_docroot_map();
    $obj->{'domain_to_docroot_map'} = $domain_to_docroot_map;

    my $resp = Cpanel::cPAddons::Instances::get_instances_with_sort($mod);
    $obj->add_error( $resp->{error} ) if $resp->{error};

    $obj->{'installed'}        = $resp->{instances}        || {};
    $obj->{'sorted_instances'} = $resp->{sorted_instances} || [];

    $obj->{'addon'} = $mod;

    $obj->{'workinginstall'} = $input_hr->{'workinginstall'} || '';
    $obj->{'workinginstall'} =~ s{\.yaml$}{};

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} } || {};

    my $domain = $input_hr->{'subdomain'} || $instance->{'domain'} || '';

    if ( exists $domain_to_docroot_map->{$domain}
        && $domain ne $Cpanel::CPDATA{'DNS'} ) {
        $obj->{'domain'}              = '';
        $obj->{'installed_on_domain'} = $domain;
        $obj->{'public_html'}         = $domain_to_docroot_map->{$domain};
    }
    else {
        $obj->{'domain'}              = $Cpanel::CPDATA{'DNS'};
        $obj->{'installed_on_domain'} = $obj->{'domain'};
        $obj->{'public_html'}         = "$Cpanel::homedir/public_html";
    }

    my $path = $input_hr->{'installdir'} || $instance->{'installdir'} || '';
    $path =~ s/\/{2,}/\//g;     # collapse any preceding slashes
    $path =~ s/[^\w\/\-]//g;    # remove things that are not \w / -
    $path =~ s/^\/+|\/+$//g;    # remove any remaining preceding or trailing slashes
    $obj->{'url'} = "$obj->{installed_on_domain}/$path";

    $obj->{'hostname'} = Cpanel::Hostname::gethostname();
    $obj->{'email'}    = $input_hr->{'email'}
      || $instance->{'email'};

    if ( !$obj->{'email'} ) {
        $obj->{'email'} = _get_contact_email( $safe_input_hr, $instance );
    }

    # Addon related data
    $obj->{'addon'}      = $mod;
    $obj->{'addon_path'} = $module_hr->{rel_folder};

    # Build the list of extract_archives to install into the install path.
    $obj->_build_archive_list($module_hr);

    $obj->{'adminarea_name'} =~ s/[^\w ]//g;

    if ( defined $input_hr->{'installdir'} || $input_hr->{'action'} eq 'install' ) {

        if ( !$path ) {

            # Allow install in root only if the addon includes some rules
            # for cleaning up the install at a fine grain level.
            $path = './' if $module_hr->{can_be_installed_in_root_of_domain};
        }
        elsif ( $path && _dir_exists("$obj->{'public_html'}/$path") ) {
            $obj->add_critical_error(
                locale()->maketext(
                    "The “[_1]” directory already exists.",
                    Cpanel::Encoder::Tiny::safe_html_encode_str("$obj->{'public_html'}/$path/"),
                )
            ) if -d "$obj->{'public_html'}/$path";
        }

        my $install_domain  = $input_hr->{'subdomain'} || $Cpanel::CPDATA{'DNS'};
        my $install_docroot = $domain_to_docroot_map->{$install_domain};

        if ( $path eq './' ) {
            for ( keys %{ $obj->{'installed'} } ) {
                next unless m/^\Q$mod\E\.\d+/;
                my $existing_install = $obj->{'installed'}->{$_};
                $obj->add_critical_error( locale()->maketext( "The [_1] directory already contains an installation of this [asis,cPAddon].", "public_html" ) )
                  if $existing_install->{'installpath'} eq './'
                  && $existing_install->{'public_html'} eq $install_docroot;
            }
        }

        $obj->{'version_key'} = $info_hr->{ $info_hr->{'version'} };
        $obj->{'installpath'} = $err ? '' : $path;

        $obj->add_critical_error( locale()->maketext("You must specify an installation directory.") )
          if !$path && $input_hr->{'action'} eq 'install';
    }

    if ( $info_hr->{'adminuser_pass'} ) {
        $obj->{'default_minimum_pass_length'} = 5;
        $obj->{'minimum_pass_strength'}       = Cpanel::PasswdStrength::Check::get_required_strength('cpaddons');

        $obj->{'username'}  = $input_hr->{'auser'}  || '';
        $obj->{'password'}  = $input_hr->{'apass'}  || '';
        $obj->{'password2'} = $input_hr->{'apass2'} || '';
        $obj->{'username'} =~ s/\W//g;

        $obj->{'salt'} =
            $info_hr->{'crypt_salt'} =~ m/^\w+$/
          ? $info_hr->{'crypt_salt'}
          : $obj->{'username'};
        $obj->{'password_crypt'} = crypt( $obj->{'password'}, $obj->{'salt'} );
        require Digest::MD5;
        require MIME::Base64;
        $obj->{'password_md5_hex'}    = Digest::MD5::md5_hex( $obj->{'password'} );
        $obj->{'password_md5_base64'} = Digest::MD5::md5_base64( $obj->{'password'} );
        $obj->{'password_base64'}     = MIME::Base64::encode_base64( $obj->{'password'} );
    }

    if ( $info_hr->{'admin_email'} ) {
        my $contactemail = $obj->{'email'} || _get_contact_email( $safe_input_hr, $instance );
        $obj->{'contactemail'} = $contactemail;
    }

    $obj->{'suexec'}    = -x apache_paths_facade->bin_suexec() ? 1 : 0;
    $obj->{'phpsuexec'} = '';

    # TODO: Move to Runtime class
    if ( $info_hr->{'setphpsuexecvar'} ) {
        $obj->{'phpsuexec'} = '-1';
        my $suexec_bin = apache_paths_facade->bin_suexec();
        if ( -r $suexec_bin ) {
            $obj->{'phpsuexec'} = `grep PHPHANDLER $suexec_bin` =~ /matches/ ? 1 : 0;
        }
    }

    # TODO: Move to Runtime class
    if ( $info_hr->{'set_php_is_running_as_user_at_this_moment'} ) {

        $obj->{'php_is_running_as_user_at_this_moment'} = '-1';

        my $phpifile = 'cpaddons_phpeuid.php';
        my $uniq     = 1;

        while ( -e "$obj->{'public_html'}/$uniq$phpifile" ) { $uniq++; }

        my $uniq_php_file = Cpanel::cPAddons::Util::_untaint("$obj->{'public_html'}/$uniq$phpifile");

        if ( open my $php_fh, '>', $uniq_php_file ) {
            print {$php_fh} qq(<?php echo posix_geteuid(); ?>);
            close $php_fh;
            if ( chmod 0755, $uniq_php_file ) {
                eval {
                    require Cpanel::HttpRequest;
                    my $phpeuid = Cpanel::HttpRequest->new( 'hideOutput' => 1 )->request(
                        'host'     => $obj->{'installed_on_domain'},
                        'url'      => '/' . $uniq . $phpifile,
                        'protocol' => 0,
                    );
                    $obj->{'set_php_is_running_as_user_at_this_moment_raw_output'} = $phpeuid;
                    chomp $phpeuid;
                    if ( int $phpeuid ) {
                        $obj->{'php_is_running_as_user_at_this_moment'} = int($phpeuid) == Cpanel::PwCache::Get::getuid('nobody') ? 0 : 1;
                    }
                };
                $obj->{'set_php_is_running_as_user_at_this_moment_error'} = $@ if $@;
            }
            unlink $uniq_php_file;
        }
    }

    # TODO: Move to Runtime class
    if ( $info_hr->{'set_phpinfo_at_this_moment'} ) {

        $obj->{'phpinfo_at_this_moment'} = '-1';

        my $phpifile = 'cpaddons_phpinfo.php';
        my $uniq     = 1;

        while ( -e "$obj->{'public_html'}/$uniq$phpifile" ) { $uniq++; }

        my $uniq_php_file = Cpanel::cPAddons::Util::_untaint("$obj->{'public_html'}/$uniq$phpifile");

        if ( open my $php_fh, '>', $uniq_php_file ) {
            print {$php_fh} qq(<?php phpinfo(); ?>);
            close $php_fh;
            if ( chmod 0755, $uniq_php_file ) {
                require Cpanel::HttpRequest;
                eval { $obj->{'phpinfo_at_this_moment'} = Cpanel::HttpRequest->new( 'hideOutput' => 1 )->request( 'host' => $obj->{'installed_on_domain'}, 'url' => "/$uniq$phpifile", 'protocol' => 0, ); };
                $obj->{'set_phpinfo_at_this_moment_error'} = $@ if $@;
            }
            unlink $uniq_php_file;
        }
    }

    require Cpanel::MysqlFE::DB;
    my %DBS = Cpanel::MysqlFE::DB::listdbs();
    $obj->{'databases'} = [ keys %DBS ];

    $obj->{'registry'} =
      exists $obj->{'installed'}->{ $input_hr->{'workinginstall'} }
      ? $input_hr->{'workinginstall'}
      : '';

    $obj->{'initial_path'} =
         $safe_input_hr->{'installdir'}
      || Cpanel::Encoder::Tiny::safe_html_encode_str( $info_hr->{'installdir'} )
      || '';

    if ( ref $info_hr->{'install_fields'} eq 'ARRAY' ) {

        # NOTE: This hash contains the standard install fields.
        # If the addon developer includes them in the install
        # fields collection, we ignore them when generating the
        # custom section of the form.
        $obj->{standard_install_fields} = {
            'addon'      => 1,
            'email'      => 1,
            'auser'      => 1,
            'apass'      => 1,
            'installdir' => 1,
            'action'     => 1,
            'debug'      => 1,
            'verbose'    => 1,
            'oneclick'   => 1,
            'autoupdate' => 1,
        };
    }

    # Copy the key/values from the input into the obj
    for ( sort keys %{$input_hr} ) {
        $obj->{"input_$_"} = $input_hr->{$_};
    }

    if ( $info_hr->{'table_prefix'} ) {
        my $tp = $input_hr->{'table_prefix'} || $instance->{'table_prefix'} || $info_hr->{'table_prefix'};

        if ( $tp =~ m/[^a-zA-Z0-9]/ ) {
            $obj->add_warning( locale->maketext('The database table prefix should only contain the letters [asis,a-z] and [asis,A-Z] and the numbers [asis,0-9]. The system will remove all other characters.') );
        }

        $tp =~ s/[^a-zA-Z0-9]+//g;
        $obj->{'table_prefix'}            = $tp;
        $obj->{'table_prefix_underscore'} = ( $tp =~ m/_$/ ? $tp : $tp . '_' );

        my $db = $input_hr->{'existing_mysql'} || $instance->{$tp} || '';
        $db =~ s/[^a-zA-Z0-9_]+//g;
        $obj->{'existing_mysql'} = $db;
    }

    $obj->{'_self'}   = $Cpanel::cPAddons::Globals::_self;
    $obj->{'user'}    = $Cpanel::user;
    $obj->{'homedir'} = $Cpanel::homedir;

    $obj->{'lang'} = $Cpanel::CPDATA{'LANG'};

    $obj->{'public_html'} ||= "$Cpanel::homedir/public_html";
    $obj->{'installdir'} = "$obj->{'public_html'}/$obj->{'installpath'}"
      if defined $obj->{'installpath'} && $obj->{'installpath'};

    # QUESTION: Shouldn't this be using https if available?
    $obj->{'url_to_install'} = qq(http://$obj->{'installed_on_domain'}/);
    $obj->{'url_to_install'} = qq(http://$obj->{'installed_on_domain'}/$obj->{'installpath'}/)
      if $obj->{'installpath'} && $obj->{'installpath'} ne './';

    $obj->{'url_to_install_admin'} = '';
    my $admin_path = $info_hr->{'adminarea_path'};
    $admin_path =~ s{^/}{};
    if ($admin_path) {
        $obj->{'url_to_install_admin'} = $obj->{'url_to_install'} . '/' . $admin_path;
        $obj->{'url_to_install_admin'} .= '/' if $obj->{'url_to_install_admin'} !~ m/\/$/;
    }

    $obj->{'no_protocol_url_to_install'} = qq($obj->{'installed_on_domain'}/);
    $obj->{'no_protocol_url_to_install'} = qq($obj->{'installed_on_domain'}/$obj->{'installpath'}/)
      if defined $obj->{'installpath'} && $obj->{'installpath'} && $obj->{'installpath'} ne './';

    $obj->{'no_protocol_url_to_install_without_trailing_slash'} = $obj->{'no_protocol_url_to_install'};
    $obj->{'no_protocol_url_to_install_without_trailing_slash'} =~ s/\/$//g;

    $obj->{'url_to_install_without_trailing_slash'} = $obj->{'url_to_install'};
    $obj->{'url_to_install_without_trailing_slash'} =~ s/\/$//g;

    $obj->{'autoupdate'} = $input_hr->{'autoupdate'} || $instance->{'autoupdate'} ? 1 : 0;

    $obj->{'version'}         = $info_hr->{'version'};
    $obj->{'mysql_version'}   = $Cpanel::CONF{'mysql-version'};
    $obj->{'postgre_version'} = '';                               # TODO: when postgre added

    my %dosuexecwarn;
    my %dophpsuexecwarn;
    my %dophpasuserwarn;

    if (   $info_hr->{'warn_php_is_running_as_user_at_this_moment_change'}
        || $info_hr->{'warnphpsuexec_change'}
        || $info_hr->{'warnsuexec_change'} ) {
        for ( keys %{ $obj->{'installed'} } ) {
            next if $_ !~ m{^$mod\\.\\d+$};

            if ( $info_hr->{'warn_php_is_running_as_user_at_this_moment_change'} ) {
                $dophpasuserwarn{$_} = $obj->{'installed'}->{$_}->{'php_is_running_as_user_at_this_moment'}
                  if $obj->{'installed'}->{$_}->{'php_is_running_as_user_at_this_moment'} ne $obj->{'php_is_running_as_user_at_this_moment'};
            }

            if ( $info_hr->{'warnsuexec_change'} ) {
                $dosuexecwarn{$_} = $obj->{'installed'}->{$_}->{'suexec'}
                  if $obj->{'installed'}->{$_}->{'suexec'} ne $obj->{'suexec'};
            }

            if ( $info_hr->{'setphpsuexecvar'} && $info_hr->{'warnphpsuexec_change'} ) {
                next
                  if $obj->{'installed'}->{$_}->{'phpsuexec'} !~ m/^1$|^0$/
                  || $obj->{'phpsuexec'} !~ m/^1$|^0$/;
                $dophpsuexecwarn{$_} = $obj->{'installed'}->{$_}->{'phpsuexec'}
                  if $obj->{'installed'}->{$_}->{'phpsuexec'} ne $obj->{'phpsuexec'};
            }
        }
    }

    $obj->{'dophpasuserwarn'} = \%dophpasuserwarn;
    $obj->{'dosuexecwarn'}    = \%dosuexecwarn;
    $obj->{'dophpsuexecwarn'} = \%dophpsuexecwarn;

    $obj->{'checked'}                  = {};
    $obj->{'action_has_prerequisites'} = {};

    $obj->{'action_has_prerequisites'}{'install'}   = Cpanel::cPAddons::Actions::has_prerequisites( 'install',   $module_hr, $input_hr, $obj, $env_hr );
    $obj->{'action_has_prerequisites'}{'upgrade'}   = Cpanel::cPAddons::Actions::has_prerequisites( 'upgrade',   $module_hr, $input_hr, $obj, $env_hr );
    $obj->{'action_has_prerequisites'}{'uninstall'} = Cpanel::cPAddons::Actions::has_prerequisites( 'uninstall', $module_hr, $input_hr, $obj, $env_hr );
    if ( $info_hr->{specialfunctions} && ref $info_hr->{specialfunctions} eq 'HASH' ) {
        foreach my $action ( keys %{ $info_hr->{specialfunctions} } ) {

            # Skip duplicates of the standard actions
            next if grep { $action eq $_ } (qw (install upgrade uninstall));
            $obj->{'action_has_prerequisites'}{$action} = Cpanel::cPAddons::Actions::has_prerequisites( 'uninstall', $module_hr, $input_hr, $obj, $env_hr );
        }
    }

    return $obj;
}

sub _get_domain_docroot_map {
    require Cpanel::DomainLookup::DocRoot;
    my $docroot_hr = Cpanel::DomainLookup::DocRoot::getdocroots();

    for my $dom ( sort keys %{$docroot_hr} ) {
        delete $docroot_hr->{$dom} if $dom =~ m{^[*]};
    }

    return $docroot_hr;
}

#### notification helper functions ##

=head2 has_notices(TYPE)

=head3 ARGUMENTS

=over

=item TYPE - String - Type of notice: critical_error, error, warning, info, success, plain, pre, html

=back

=head3 RETURNS

1 if the notices collection has any matching the type, 0 otherwise.

=cut

sub has_notices() {
    my ( $self, $type ) = @_;
    return $self->{notices}->has($type) ? 1 : 0;
}

=head2 add_critical_error(MESSAGE)

=cut

sub add_critical_error {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_critical_error( $message, %opts );
}

=head2 add_error(MESSAGE)

=cut

sub add_error {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_error( $message, %opts );
}

=head2 add_warning(MESSAGE)

=cut

sub add_warning {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_warning( $message, %opts );
}

=head2 add_info(MESSAGE)

=cut

sub add_info {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_info( $message, %opts );
}

=head2 add_success(MESSAGE)

=cut

sub add_success {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_success( $message, %opts );
}

=head2 add_plain(MESSAGE)

=cut

sub add_plain {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_plain( $message, %opts );
}

=head2 add_pre(MESSAGE)

=cut

sub add_pre {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_pre( $message, %opts );
}

=head2 add_html(MESSAGE)

=cut

sub add_html {
    my ( $self, $message, %opts ) = @_;
    return $self->{notices}->add_html( $message, %opts );
}

#### standard action functions ##

=head2 stdinstall(OBJ, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

cPAddons modules under /usr/local/cpanel/cpaddons/ call this method to perform an install.

=cut

sub stdinstall {    ## no critic (ProhibitManyArgs) -- legacy code that is part of an interface
    my ( $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;

    local $| = 1;

    if ( Cpanel::cPAddons::Util::_there_are_missing_whm_addons( $info_hr, $obj ) ) {
        return;
    }

    if ( !_chdir( $obj->{'public_html'} ) ) {
        logger()->info("Could not change directory into public_html: $!");
        $obj->add_critical_error( locale()->maketext( "The system could not open the public_html directory: [_1]", Cpanel::Encoder::Tiny::safe_html_encode_str($!) ) );
        return;
    }

    if ( !Cpanel::cPAddons::License::check_license( $obj, $info_hr, $input_hr ) ) {
        $obj->add_critical_error(
            locale()->maketext(
                "The system could not validate the license for this [asis,cPAddon].",
            )
        );
        return;
    }

    if ( $obj->{'installpath'} ne './' && _dir_exists( $obj->{'installpath'} ) ) {
        $obj->add_critical_error(
            locale()->maketext(
                "The installation path “[_1]” already exists.",
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'installpath'} ),
            )
        );
        return;
    }

    $obj->{'installpath'} = Cpanel::cPAddons::Util::_untaint( $obj->{'installpath'} );
    my $dir_is_good = $obj->{'installpath'} eq './' ? 1 : Cpanel::SafeDir::MK::safemkdir( $obj->{'installpath'} );
    if ($dir_is_good) {

        if ( !_chdir( $obj->{'installpath'} ) ) {
            logger()->info("Could not change into install dir ($obj->{'installpath'}): $!");
            $obj->add_critical_error(
                locale()->maketext(
                    "The system could not open the install directory [_1]: [_2]",
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'installpath'} ),
                    Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                )
            );
            return;
        }

        my $ok    = 1;
        my @steps = (
            'untar_archives',
            'secure_admin_area',
            'check_perl_modules',
            'create_dbs',
            'process_config_file',
            'process_install_scripts',
            'process_chmod',
            'process_chgrp',
            '_do_phpsuexec_perms',
            'process_security_check',
            'add_cron'
        );

        for my $step (@steps) {
            die "Method $step not available on session object." if !$obj->can($step);
            $obj->add_pre("Processing $step")                   if $obj->{verbose};
            $ok = $obj->$step( $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );
            last if !$ok || $obj->has_notices('critical_error');
        }

        # Mark the install time
        $obj->{"installed_$info_hr->{'version'}"} = time();

        if ( !$obj->has_notices('critical_error') ) {

            # The install at least partly succeeded

            # Save the changes to the registration system.
            if ( !$obj->register() ) {
                $obj->add_error( locale()->maketext('The system cannot create the registry. In this condition, the system cannot manage or upgrade this installation from this interface.') );
                return;
            }

            # Attempt to run the post install steps
            my @post = (
                'process_import_file',
            );

            for my $step (@post) {
                die "Post method $step not available on session object." if !$obj->can($step);
                $ok = $obj->$step( $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );
                last if !$ok || $obj->has_notices('critical_error');
            }
        }

        if ( !$obj->has_notices('critical_error') ) {
            if ( !$obj->has_notices('error') ) {
                $obj->{success} = 1;
                $obj->add_success( locale->maketext('Done!') );
                return 1;
            }
            else {
                $obj->{partial_success} = 1;
                $obj->add_warning( locale->maketext('The installation failed, but you can attempt to complete the installation manually. Review the error messages for more details. Your website may not function as intended until you correct the errors.') );
            }
        }
        else {
            $obj->add_pre( locale()->maketext('Cleaning up failed install …') ) if $obj->{verbose};
            if ( !_chdir( $obj->{'public_html'} ) ) {
                logger()->info("Could not go into public_html: $!");
                $obj->add_error(
                    locale()->maketext(
                        'The system could not open the [_1] directory: [_2]',
                        'public_html',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($!)
                    )
                );
            }
            else {
                Cpanel::cPAddons::Util::remove_install_directory( $obj->{'installpath'}, $info_hr );
                $obj->add_critical_error( locale()->maketext('The installation failed with the above errors.') );
            }
        }
    }
    else {
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not create the “[_1]” installation path: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{installpath} ),
                Cpanel::Encoder::Tiny::safe_html_encode_str($!),
            )
        );
    }
    return 0;    # failure
}

=head2 stdupgrade(OBJ, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

cPAddons modules under /usr/local/cpanel/cpaddons/ call this method to perform an upgrade.

=cut

sub stdupgrade {    ##no critic(ProhibitExcessComplexity,ProhibitManyArgs) -- legacy code
    my ( $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;

    local $| = 1;

    # Basic sanity check
    if ( !chdir $obj->{'homedir'} ) {
        my $exception = $!;
        logger()->info("Could not go into user's home directory, $obj->{'homedir'}: $exception");
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not open the user’s “[_1]” home directory: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'homedir'} ),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );

        return;
    }

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };

    if ( !$instance ) {
        $obj->add_critical_error(
            locale->maketext(
                'The system could not locate the “[_1]” instance that you wish to upgrade.',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'workinginstall'} ),
            )
        );
        return;
    }

    # Sanitize installdir
    $instance->{'installdir'} =~ s/\/$//;

    my $current_addon_version = $instance->{'version'};
    my $upgraders_dir         = "$Cpanel::cPAddons::Globals::Static::base/$instance->{'addon_path'}/upgrade";
    my %all_upgraders;

    if ( opendir my $up_dh, $upgraders_dir ) {
        @all_upgraders{ grep !/^\.+$/, readdir $up_dh } = ();
        closedir $up_dh;
    }
    else {
        my $exception = $!;
        logger()->info("Could not read upgrade dir, $upgraders_dir: $!");
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not read the “[_1]” upgrade directory: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($upgraders_dir),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return;
    }

    # Find the correct upgrader for this version.
    # Directories are named with:  <current_version>_<new_version>
    my $upgrade = '';
    for ( sort keys %all_upgraders ) {
        next unless m/^\Q$current_addon_version\E\_\d+/;
        $upgrade = $_;
    }
    $upgrade =~ s/\/$//g;
    if ( !$upgrade ) {
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not locate a compatible update for the current version: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($current_addon_version),
            )
        );
        return;
    }

    my ( $oldver, $newver ) = split /_/, $upgrade;

    if ( !Cpanel::cPAddons::License::check_license( $obj, $info_hr, $input_hr, $instance ) ) {
        return;
    }

    my $update_directory_suffix = '.cpaddons_upgrade';
    my $update_directory        = $obj->{'homedir'} . '/' . $update_directory_suffix;

    # Remove any older upgrade attempts
    Cpanel::SafeDir::RM::safermdir($update_directory);
    if ( _dir_exists($update_directory) ) {
        logger()->info("Previous upgrade directory at, $update_directory, still exists after attempting to remove it.");
        $obj->add_critical_error(
            locale()->maketext(
                'The system failed to remove previous upgrade directory: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($update_directory),
            )
        );
        return;
    }

    if ( !Cpanel::SafeDir::MK::safemkdir( $update_directory, '0755' ) ) {
        my $exception = $!;
        logger()->info("Could not create upgrade directory, $update_directory: $exception");
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not create the “[_1]” upgrade directory: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($update_directory),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return;
    }
    else {
        $obj->add_pre( locale()->maketext( 'The system created the upgrade directory: [_1]', $update_directory ) ) if $obj->{debug};
    }

    if ( !_chdir($update_directory) ) {
        my $exception = $!;
        logger()->info("Could not change into working directory, $update_directory: $exception");
        $obj->add_critical_error(
            locale()->maketext(
                'The system could not change into the “[_1]” upgrade working directory: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($update_directory),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return;
    }

    use Cwd;
    my $pwd = Cwd::getcwd();

    $obj->add_pre( locale()->maketext( 'Copying files to the “[_1]” upgrade directory …', $update_directory ) ) if $obj->{debug};

    my $copy_to_working_folder_ok = 0;
    if ( $instance->{'installpath'} eq './' ) {

        # Root of domain install to upgrade
        # Copy the files from the install folder
        # to the upgrade working folder.
        my $move_fail_count = 0;
        for my $file_collection_name (
            qw(
            public_html_install_files
            public_html_install_dirs
            public_html_install_unknown)
        ) {

            last if $move_fail_count;

            my $files_and_folders = $info_hr->{$current_addon_version} || $info_hr->{all_versions};
            my $files_in_version  = $files_and_folders->{$file_collection_name};
            next if !$files_in_version || ref $files_in_version ne 'ARRAY';
            for my $file_path ( @{$files_in_version} ) {
                my $source = "$instance->{'public_html'}/$file_path";
                if ( $file_collection_name ne 'public_html_install_files' ) {
                    $source .= '/*' unless $source =~ m/[*?]/;

                    # if they are directories (i.e not
                    # 'public_html_install_files') do the
                    # glob-like value unless they are
                    # already glob-like
                }

                my $destination = './' . $file_path;

                require Cpanel::FileUtils::Copy;
                $copy_to_working_folder_ok = Cpanel::FileUtils::Copy::safecopy( $source, $destination );
                if ( !$copy_to_working_folder_ok ) {
                    $move_fail_count++;
                    $obj->add_pre(
                        locale()->maketext(
                            'The system could not copy the “[_1]” folder to working folder “[_2]”.',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($source),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($destination),
                        )
                    );
                    last;
                }
            }
        }
    }
    else {
        # Subdirectory install to upgrade
        # Just copy everything from the install
        # directory to the upgrade working folder.
        my $source_directory = $instance->{'installdir'} . '/*';

        require Cpanel::FileUtils::Copy;
        $copy_to_working_folder_ok = Cpanel::FileUtils::Copy::safecopy( $source_directory, $update_directory );
    }

    if ($copy_to_working_folder_ok) {

        my $full_path_to_update_dir = Cwd::abs_path();

        # we've copied the files and are in the upgrade
        # working directory so lets catalog what we have
        # before making any modifications.
        my @copy_manifest;

        # how do we know if find() had an error reading anything?
        # TODO: set @iter_err and report below
        require Cpanel::SafeFind;
        Cpanel::SafeFind::find(
            {
                'follow_skip' => 1,
                'untaint'     => 1,
                'no_chdir'    => 1,
                'wanted'      => sub {
                    return if $File::Find::name eq '.' || $File::Find::name eq './';
                    my ($copy) = $File::Find::name =~ m/(.*)/;    # just in case there is any "global var" weirdness
                    push @copy_manifest, $copy;
                },
            },
            '.'
        );

        my $public_html = $obj->{'public_html'};
        my $buopt       = '--basename-prefix=.cpaddon_diff_backup_' . $obj->{'workinginstall'};
        my $tmpfile     = Cpanel::Rand::get_tmp_file_by_name( "$Cpanel::homedir/tmp/", '.cpaddons_upgrade-', $Cpanel::Rand::TYPE_FILE, $Cpanel::Rand::SKIP_OPEN );

        $obj->{has_patch} = -e "$upgraders_dir/$upgrade/diff" ? 1 : 0;

        # Preflight check the patch if it exists.
        my $forced = $input_hr->{'force'} eq $Cpanel::cPAddons::Globals::force_text ? 1 : 0;
        $obj->{forced} = $forced;

        my $patch_test_output = '';
        if ( $obj->{has_patch} ) {
            $obj->add_pre(
                locale()->maketext(
                    'Copying patch …',
                )
            ) if $obj->{verbose};

            require Cpanel::FileUtils::Copy;
            Cpanel::FileUtils::Copy::safecopy( "$upgraders_dir/$upgrade/diff", $tmpfile );

            $obj->add_pre(
                locale()->maketext(
                    'Preparing patch …',
                )
            ) if $obj->{verbose};

            $obj->procconfigfile( [$tmpfile], $instance );

            $obj->add_pre(
                locale()->maketext(
                    'Testing patch …',
                )
            ) if $obj->{verbose};

            my $dry_run_flag = Cpanel::cPAddons::Util::_get_patch_dry_run_flag();
            require Cpanel::SafeRun::Object;
            my $run = Cpanel::SafeRun::Object->new(
                program => 'patch',
                args    => [
                    '--remove-empty-files',
                    '-p1',
                    '-F99',
                    '-s',
                    '-i',
                    $tmpfile,
                    $dry_run_flag,
                    $buopt,
                ],
            );

            if ( !$run ) {
                $obj->add_critical_error(
                    locale()->maketext(
                        'The system could not apply the “[_1]” patch because the process failed to run.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str("$upgraders_dir/$upgrade/diff")
                    )
                );
                return;
            }
            elsif ( my $error = $run->error_code() ) {
                $patch_test_output = $run->stderr() || $run->stdout();
                chomp $patch_test_output;

                # Note, its not critical since we
                # are only testing the patch here
                # so should not exit.
                $obj->add_error(
                    locale()->maketext(
                        'The system could not apply the “[_1]” patch and returned the following error code: [_2]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str("$upgraders_dir/$upgrade/diff"),
                        $error
                    )
                );
                $obj->{patch_failed}      = 1;
                $obj->{patch_test_output} = $patch_test_output;
                return unless $forced;
            }
            else {
                my $out = $run->stdout();
                chomp($out);
                $obj->add_pre($out) if $out && $obj->{verbose};
            }
        }

        if (
            !$obj->{has_patch}                                   # No patch provided
            || ( $obj->{has_patch} && !$obj->{patch_failed} )    # Patch applies cleanly
            || $forced                                           # User decided to force the patch
          ) {                                                    # Patch does not apply cleanly, but the user agrees to force it.

            if ($forced) {
                $obj->add_pre(
                    locale()->maketext(
                        'Starting forced upgrade from “[_1]” to “[_2]” …',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($current_addon_version),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($newver),
                    )
                );
            }
            else {
                $obj->add_pre(
                    locale()->maketext(
                        'Starting upgrade from “[_1]” to “[_2]” …',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($current_addon_version),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($newver),
                    )
                );
            }

            # Apply the patch if it exists.
            if ( $obj->{has_patch} ) {

                $obj->add_pre(
                    locale()->maketext(
                        'Applying patch: [_1]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($tmpfile)
                    )
                ) if $obj->{debug};

                # Apply the patch for real.
                my $patch_run_output = '';

                require Cpanel::SafeRun::Object;
                my $run = Cpanel::SafeRun::Object->new(
                    program => 'patch',
                    args    => [
                        '--remove-empty-files',
                        '-p1',
                        '-F99',
                        '-i',
                        $tmpfile,
                        $buopt,
                    ],
                );

                if ( !$run ) {
                    $obj->add_critical_error(
                        locale()->maketext(
                            'The system could not apply the patch: [_1]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str("$upgraders_dir/$upgrade/diff"),
                        )
                    );
                    return;
                }
                elsif ( my $error = $run->error_code() ) {
                    $patch_run_output = $run->stderr() || $run->stdout();
                    chomp $patch_run_output;

                    $obj->add_critical_error(
                        locale()->maketext(
                            'The system could not apply the “[_1]” patch and returned the following error code: [_2]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str("$upgraders_dir/$upgrade/diff"),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($error),
                        )
                    );
                    $obj->{patch_failed}      = 1;
                    $obj->{patch_test_output} = $patch_run_output;
                    return unless $forced;
                }
                else {
                    my $out = $run->stdout();
                    chomp($out);
                    $obj->add_pre($out) if $out && $obj->{verbose};
                }

                $obj->add_pre( locale()->maketext('The upgrade patch completed.') )
                  if $obj->{verbose};
            }

            # Run any scripts provided
            my $upgrade_script = "$upgraders_dir/$upgrade/script";
            if ( -e $upgrade_script && -x $upgrade_script ) {

                $obj->add_pre(
                    locale()->maketext(
                        'Running “[_1]” upgrade script …',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($upgrade_script)
                    )
                ) if $obj->{verbose};

                require Cpanel::SafeRun::Object;
                my $run = Cpanel::SafeRun::Object->new(
                    program => $upgrade_script,
                );

                if ( !$run ) {
                    $obj->add_critical_error(
                        locale()->maketext(
                            'The system failed to run upgrade script: [_1]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($upgrade_script),
                        )
                    );
                    return;
                }
                elsif ( my $error = $run->error_code() ) {
                    my $err_msg = $run->stderr();
                    chomp $err_msg;

                    $obj->add_error(
                        locale()->maketext(
                            'The system failed to run the “[_1]” upgrade script with error code “[_2]”: [_3]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($upgrade_script),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($error),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($err_msg),
                        )
                    );
                }
                else {
                    my $out = $run->stdout();
                    chomp($out);
                    $obj->add_pre($out) if $out && $obj->{verbose};
                }
            }

            # Run mysql upgrade script if its present.
            my $mysql_script = "$upgraders_dir/$upgrade/mysql";
            if ( !$obj->my_dosql( $mysql_script, $instance, $instance->{mysql_user}, $instance->{mysql_pass} ) ) {
                $obj->add_error(
                    locale()->maketext(
                        'The system could not run the “[_1]” [asis,SQL] file on the [asis,MySQL] databases. You must run the file manually.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($mysql_script),
                    )
                );
            }

            # Run postgre upgrade script if its present.
            my $postgres_script = "$upgraders_dir/$upgrade/postgre";
            if ( !$obj->pg_dosql($postgres_script) ) {
                $obj->add_error(
                    locale()->maketext(
                        'The system could not run the “[_1]” [asis,SQL] file on the [asis,Postgre] databases. You must run the file manually.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($postgres_script),
                    )
                );
            }

            if ( !chdir $public_html ) {
                my $exception = $!;
                $obj->add_error(
                    locale()->maketext(
                        'The system could not open the “[_1]” directory after the upgrade: [_2]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($public_html),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                    )
                );
                return;
            }

            $obj->procconfigfile(
                $info_hr->{'config_files'},
                $instance,
                $full_path_to_update_dir,
                $instance->{'installdir'},
            );

            $instance->{'version_key'}         = $info_hr->{$newver};
            $instance->{'version'}             = $newver;
            $instance->{"upgraded_to_$newver"} = time();

            my $persist = get_persistence_data($instance);

            my $install_registry_path = "$Cpanel::homedir/.cpaddons/$obj->{'workinginstall'}";
            if ( !Cpanel::cPAddons::Cache::write_cache( $install_registry_path, $persist ) ) {
                $obj->add_critical_error(
                    locale()->maketext(
                        'The system could not save the upgrade information to the “[_1]” registry file. In this condition, you may lose the ability to manage this [asis,cPAddon] with the interface.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($install_registry_path),
                    )
                );
                return;
            }
            else {
                $obj->add_pre(
                    locale()->maketext(
                        'The system saved the updated configuration to: [_1]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($install_registry_path),
                    )
                ) if $obj->{verbose};
            }

            my $destination = $instance->{'installdir'};

            require Cpanel::FileUtils::Copy;
            if ( !Cpanel::FileUtils::Copy::safecopy( "$full_path_to_update_dir/*", $destination ) ) {
                $obj->add_critical_error(
                    locale()->maketext(
                        'The system could not move the update from the temporary directory to the production directory. You must move the files in the “[_1]” directory to the “[_2]” directory manually.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($full_path_to_update_dir),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($destination),
                    )
                );
            }
            else {

                $obj->add_pre(
                    locale()->maketext(
                        'The system copied the upgraded application back to: [_1]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($destination),
                    )
                ) if $obj->{verbose};

                # we've copied everything back
                # so now remove any files that
                # disappear during update (patch, script, etc)
                $obj->add_pre(
                    locale()->maketext(
                        'Cleaning up any obsolete files or directories …',
                    )
                ) if $obj->{verbose};

                my @removed;
                for my $path ( reverse @copy_manifest ) {
                    my $clean_path = $path;
                    $clean_path =~ s{^\.\/}{};

                    next if -l "$full_path_to_update_dir/$clean_path";
                    if ( !-e "$full_path_to_update_dir/$clean_path" ) {
                        my $remove = "$instance->{'installpath'}/$clean_path";
                        if ( -d $remove ) {
                            if ( !Cpanel::SafeDir::RM::safermdir($remove) ) {
                                my $exception = $!;
                                $obj->add_warning(
                                    locale()->maketext(
                                        'The system could not remove the “[_1]” directory: [_2]',
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($remove),
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                                    )
                                );
                            }
                            else {
                                push @removed, Cpanel::Encoder::Tiny::safe_html_encode_str($remove);
                            }
                        }
                        else {
                            if ( !unlink $remove ) {
                                my $exception = $!;
                                $obj->add_warning(
                                    locale()->maketext(
                                        'The system could not remove the “[_1]” file: [_2]',
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($remove),
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                                    )
                                );
                            }
                            else {
                                push @removed, Cpanel::Encoder::Tiny::safe_html_encode_str($remove);
                            }
                        }
                    }
                }

                $obj->add_pre(
                    locale()->maketext(
                        'The system removed the following obsolete files or directories:',
                    ),
                    list_items => \@removed,
                ) if $obj->{debug} && @removed;

                if ( chdir $public_html ) {
                    if ( !$obj->{debug} && !Cpanel::SafeDir::RM::safermdir($full_path_to_update_dir) ) {
                        my $exception = $!;
                        logger()->info("Could not clean up $full_path_to_update_dir");
                        $obj->add_warning(
                            locale()->maketext(
                                'The system could not remove the “[_1]” directory: [_2]',
                                Cpanel::Encoder::Tiny::safe_html_encode_str($full_path_to_update_dir),
                                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                            )
                        );
                    }
                }
                else {
                    $obj->add_warning(
                        locale()->maketext(
                            'The system could not open the home directory in order to remove the “[_1]” directory: [_2]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($full_path_to_update_dir),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                        )
                    );
                }
            }

            my $remove_path = "$upgraders_dir/$upgrade/remove";
            if ( -e $remove_path ) {

                $obj->add_pre(
                    locale()->maketext(
                        'The system is removing the files or directories that the upgrade specified …',
                    )
                ) if $obj->{verbose};

                my @removed;
                if ( open my $rem_fh, '<', $remove_path ) {
                    while (<$rem_fh>) {
                        chomp;
                        next if !$_;
                        my $remove = "$instance->{'installpath'}/$_";
                        next if !-e $remove;

                        if ( -d $remove ) {
                            if ( !Cpanel::SafeDir::RM::safermdir($remove) ) {
                                $obj->add_warning(
                                    locale()->maketext(
                                        'The system could not remove the “[_1]” directory: [_2]',
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($remove),
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                                    )
                                );
                            }
                            else {
                                push @removed, Cpanel::Encoder::Tiny::safe_html_encode_str($remove);
                            }
                        }
                        else {
                            if ( !unlink $remove ) {
                                $obj->add_warning(
                                    locale()->maketext(
                                        'The system could not remove the “[_1]” file: [_2]',
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($remove),
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                                    )
                                );
                            }
                            else {
                                push @removed, Cpanel::Encoder::Tiny::safe_html_encode_str($remove);
                            }
                        }
                    }
                    close $rem_fh;

                    $obj->add_pre(
                        locale()->maketext(
                            'The system removed the following obsolete files or directories:',
                        ),
                        list_items => \@removed,
                    ) if $obj->{debug} && @removed;
                }
            }

            # Process the chmod file to set the correct permission for all the files
            my $chmod_path = "$upgraders_dir/$upgrade/chmod";
            if ( -e $chmod_path ) {
                if ( open my $chmod_fh, '<', $chmod_path ) {
                    $obj->add_pre(
                        locale()->maketext(
                            'Adjusting file and directory permissions …',
                        )
                    ) if $obj->{verbose};

                    my @changed;
                    while (<$chmod_fh>) {
                        chomp;
                        next if !$_;

                        # Line format is:
                        # <octal mode> <file|dir>\n
                        my ( $mode, $file ) = split /\s+/;

                        next if !$file;
                        my $file_path = "$instance->{'installpath'}/$file";

                        next if !-e $file_path;
                        next if $mode !~ m/^(\d+)$/;
                        $mode = $1;

                        if ( !chmod oct($mode), $file_path ) {
                            $obj->add_warning(
                                locale()->maketext(
                                    'The system could not chmod the “[_1]” file to “[_2]”: “[_3]” You must modify the file permissions manually.',
                                    Cpanel::Encoder::Tiny::safe_html_encode_str($file_path),
                                    Cpanel::Encoder::Tiny::safe_html_encode_str($mode),
                                    Cpanel::Encoder::Tiny::safe_html_encode_str($!)
                                )
                            );
                        }
                        else {
                            push @changed, Cpanel::Encoder::Tiny::safe_html_encode_str("$file_path ($mode)");
                        }
                    }
                    close $chmod_fh;

                    $obj->add_pre(
                        locale()->maketext(
                            'The system changed the permissions on the following files or directories:',
                        ),
                        list_items => \@changed,
                    ) if $obj->{debug} && @changed;
                }
            }

            $obj->remove_cron();
            $obj->add_cron($info_hr);

            # Find the next upgrader in the progression
            my $next = 0;
            for my $ver ( sort keys %all_upgraders ) {
                next unless $ver =~ m/^\Q$newver\E\_\d+/;
                $next = $ver;
            }

            # If we found another upgrader in the progression
            if ($next) {

                # Process the next upgrade in the progression.
                my ( undef, $nxtstp ) = split /_/, $next;
                $obj->{'installs'}->{ $obj->{'workinginstall'} } = $instance;
                $obj->stdupgrade( $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );    # Recursive??? ick
            }
            else {
                if ( $obj->has_notices( 'critical_error', 'error' ) ) {
                    if ( $obj->{forced} ) {
                        $obj->add_warning( locale()->maketext("You attempted to force an upgrade on a modified [asis,cPAddon]. The upgrade process completed but returned errors. The [asis,cPAddon] may be non-functional.") );
                    }
                    else {
                        $obj->add_warning( locale()->maketext("The system completed the upgrade but the above errors occurred. The [asis,cPAddon] may not function as expected. You can manually resolve the issue or uninstall the [asis,cPAddon].") );
                    }
                }
                else {
                    $obj->add_success( locale()->maketext("Upgrade complete.") );
                }
            }

            return 1;
        }
        else {

            if ( chdir $public_html ) {
                if ( !Cpanel::SafeDir::RM::safermdir($full_path_to_update_dir) ) {
                    my $exception = $!;
                    logger()->info("Could not clean up $full_path_to_update_dir: $exception");
                    $obj->add_warning(
                        locale->maketext(
                            'The system could not remove the “[_1]” directory: [_2]',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($full_path_to_update_dir),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                        )
                    );
                }
            }
            else {
                my $exception = $!;
                $obj->add_warning(
                    locale->maketext(
                        'The system could not open the “[_1]” directory to remove “[_2]”: [_3]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($public_html),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($full_path_to_update_dir),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                    )
                );
            }

            $obj->{show_converted} = defined $instance->{'converted'} && $instance->{'converted'} =~ m/^\d+$/;
        }
        unlink $tmpfile;
    }
    else {
        $obj->add_error(
            locale()->maketext(
                'The system could not prepare the working directory: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($!)
            )
        );
    }
    return 0;
}

=head2 stduninstall(OBJ, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

cPAddons modules under /usr/local/cpanel/cpaddons/ call this method to perform an uninstall.

=cut

sub stduninstall {    ## no critic (ProhibitManyArgs) -- legacy code that is part of an interface
    my ( $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;

    local $| = 1;

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };

    if ( !$instance ) {
        $obj->add_critical_error(
            locale->maketext(
                'The system could not locate the “[_1]” instance that you wish to uninstall.',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'workinginstall'} ),
            )
        );
        return;
    }

    if ( !$instance->{'public_html'} ) {
        $obj->add_critical_error(
            locale->maketext(
                'The configuration file for the “[_1]” instance does not contain an install folder.',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'workinginstall'} ),
            )
        );
        return;
    }

    if ( !_exists( $instance->{'public_html'} ) ) {
        $obj->add_critical_error(
            locale->maketext(
                'The “[_1]” install folder does not exist.',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $instance->{'public_html'} ),
            )
        );
    }

    if ( !_chdir( $instance->{'public_html'} ) ) {
        my $exception = $!;
        logger()->info("Could not go into $instance->{'public_html'}: $exception");
        $obj->add_critical_error(
            locale->maketext(
                'The system could not open the “[_1]” directory: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $instance->{'public_html'} ),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return;
    }

    my $udir = $instance->{'installpath'};
    $udir =~ s/^\/|\/$//g unless $udir eq './';

    # subdomain_name, subdomain_path logic remains for
    # backward compatible, see case 4666
    if (   $instance->{'subdomain_name'}
        && $udir eq $instance->{'subdomain_path'} ) {
        if ( !chdir $instance->{'subdomain_path'} ) {
            my $exception = $!;
            logger()->info("Could not go into subdomain base: $exception");
            $obj->add_critical_error(
                locale->maketext(
                    'The system could not open the subdomain’s “[_1]” directory: [_2]',
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $instance->{'subdomain_path'} ),
                    Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                )
            );
            return;
        }

        $udir = './';
    }

    if ( Cpanel::cPAddons::Util::remove_install_directory( $udir, $info_hr, $instance->{'version'} ) ) {

        my $ok    = 1;
        my @steps = (
            'process_uninstall_scripts',
            'remove_cron',
            'my_dropdbs',
            'pg_dropdbs',
            'unregister',
            'unlink_copy',
            'removepasswd',
        );

        for my $step (@steps) {
            die "Method $step not available on session object." if !$obj->can($step);
            $obj->add_pre("Processing $step")                   if $obj->{verbose};
            $ok = $obj->$step( $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );
            last if !$ok || $obj->has_notices('critical_error');
        }

        $obj->add_success( locale()->maketext('Done!') );
        return 1;
    }
    else {
        my $exception = $!;
        $obj->add_critical_error(
            locale->maketext(
                'The system could not remove the “[_1]” install directory: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($udir),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
    }
    return 0;
}

=head2 unlink_copy(OBJ)

Delete the files belonging to this instance. This is used for uninstalls.

=cut

sub unlink_copy {
    my ($obj) = @_;
    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };

    my $ok = 1;
    for ( keys %{ $instance->{'copy'} } ) {
        my $unlinkfile = Cpanel::cPAddons::Util::_untaint("$obj->{'public_html'}/$_");
        if ( _exists($unlinkfile) && !_unlink($unlinkfile) ) {
            $obj->add_error(
                locale->maketext(
                    'The system could not remove the “[_1]” file. You must remove the file manually.',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($unlinkfile),
                )
            );
            $ok = 0;
        }
    }
    return $ok;
}

sub _exists {
    my ($thing) = @_;
    return -e $thing;
}

sub _dir_exists {
    my ($dir) = @_;
    return -d $dir;
}

sub _unlink {
    my ($file) = @_;
    return unlink $file;    # builtin unlink can't accept a list
}

sub _chdir {
    my ($dir) = @_;
    return chdir $dir;
}

# NOTE: Can remove after we check our addons to verify it not used
# anymore. Its disabled else where in the code too.
sub movecopy {
    my ($obj) = @_;
    $obj->add_warning( locale()->maketext('The system temporarily disabled this feature to enable [asis, addon] domain and subdomain non-main docroot support.') );    # see case 2006
    return;
}

#### supporting functions ##

=head2 removepasswd(OBJ, INFO_HR)

Remove the htpasswd file, if any, for this instance. This is used for uninstalls.

=cut

sub removepasswd {
    my ( $obj, $info_hr ) = @_;

    my $rel_path = $info_hr->{'adminarea_path'} if defined $info_hr->{'adminarea_path'};
    return 1                                    if !$rel_path;                             # Assumes password protected directories are sub-directories of the install path.

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };
    my $dir      = "$instance->{'installpath'}/$rel_path";
    $dir = Cpanel::cPAddons::Util::_untaint($dir);

    return 0 if !$dir || !_dir_exists("$Cpanel::homedir/.htpasswds/$dir/");

    my $unlinkfile = Cpanel::cPAddons::Util::_untaint("$Cpanel::homedir/.htpasswds/$dir/passwd");
    if ( _exists($unlinkfile) && !_unlink($unlinkfile) ) {
        my $exception = $!;
        $obj->add_error(
            locale()->maketext(
                'The system could not remove the “[_1]” admin area passwd file: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($unlinkfile),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return 0;
    }

    # Remove any empty folders left behind.
    my @rmpath = split /\//, $dir;
    while (@rmpath) {

        rmdir( "$Cpanel::homedir/.htpasswds/" . join( '/', @rmpath ) ) if @rmpath;

        # no warn/die because if the sub directories are
        # not empty we don't want them removed.
        pop @rmpath;
    }
    return 1;
}

=head2 my_createdbs(OBJ, [DB_AR])

Create the database for this instance. This is used for installs.

=cut

sub my_createdbs {    ## no critic(ProhibitExcessComplexity)
    my $obj   = shift;
    my $db_ar = shift || [];

    local $Cpanel::Parser::Vars::trap_defaultfh = 1;
    my $alive = `/usr/local/cpanel/bin/cpmysqlwrap ALIVE`;
    if ( !$alive ) {
        print locale()->fetch( q{The [_1] service appears to be down. Please contact your administrator.}, 'MySQL' ) . '<br />';
        return 0;
    }
    my $needs = @{$db_ar};
    if ($needs) {
        my ( $ok, $cnt ) = Cpanel::cPAddons::Util::checkmaxdbs();
        my $nume = $Cpanel::CPDATA{'MAXSQL'} =~ m/^\d+$/ ? $Cpanel::CPDATA{'MAXSQL'} : 999999;

        # Verify we have enough dbs left in our limit
        if ( !$obj->{'existing_mysql'} && ( !$ok || ( $cnt + $needs ) > $nume ) ) {
            $obj->add_critical_error(
                locale()->maketext(
                    'This feature requires [_1] additional [asis,MySQL] [numerate,_1, database,databases]. Your current plan limits your account to [quant,_2,database,databases].',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($needs),
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $Cpanel::CPDATA{MAXSQL} ),
                )
            );
            return 0;
        }
        else {
            require Cpanel::Validate::DB::User;
            for my $db ( @{$db_ar} ) {

                #Prefix the names of any generated DBs or DBusers with the username.
                my $prefixed_db = $Cpanel::user . '_' . $db;

                my $new_dbuser = Cpanel::cPAddons::Util::find_unused_name( $Cpanel::user, $db, \&Cpanel::cPAddons::Util::_does_dbuser_exist, Cpanel::Validate::DB::User::get_max_mysql_dbuser_length() );

                my $rndpass = $obj->{'mysql_pass'} || Cpanel::cPAddons::Util::generate_mysql_password();
                $obj->{'mysql_pass'} = $rndpass if !$obj->{'mysql_pass'};
                if ( !$obj->{'table_prefix'} ) {
                    $obj->{'table_prefix'}            = $new_dbuser;
                    $obj->{'table_prefix_underscore'} = $new_dbuser . '_';
                }
                $obj->{'mysql_user_post'} = $new_dbuser if !$obj->{'mysql_user_post'};
                $obj->{'mysql_user'}      = $obj->{mysql_user_post};
                $obj->{'mysql_db_name'}   = $obj->{existing_mysql};
                $obj->{'mysql_user'}      = Cpanel::cPAddons::Util::_untaint( $obj->{'mysql_user'} );
                $rndpass                  = Cpanel::cPAddons::Util::_untaint($rndpass);

                local $ENV{'REMOTE_USER'} = $Cpanel::user;
                eval { Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'CREATE_USER', $obj->{'mysql_user'}, $rndpass ); };
                if ( my $exception = $@ ) {
                    $obj->add_critical_error(
                        locale()->maketext(
                            "The system could not create the database user: [_1]",
                            Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::Exception::get_string($exception) ),
                        )
                    );
                    return 0;
                }

                if ( $obj->{'existing_mysql'} ) {
                    if ( !Cpanel::cPAddons::Util::_does_db_exist( $obj->{'existing_mysql'} ) ) {
                        $obj->add_critical_error( locale()->maketext('Specify a valid database.') );
                        return 0;
                    }

                    my $tablesexist = 0;
                    require Capture::Tiny;
                    require Cpanel::SafeRun::API;
                    my ( $out, $err, $exit ) = Capture::Tiny::capture(
                        sub {
                            Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'ADDUSERDB', $obj->{'existing_mysql'}, $obj->{'mysql_user'}, 'ALL' );
                        }
                    );

                    chomp($out);
                    chomp($err);

                    if ( $exit || $err ) {
                        $obj->add_critical_error( locale()->maketext( "The system could not grant the user access to the database: [_1]", Cpanel::Encoder::Tiny::safe_html_encode_str($err) ) );
                        return 0;
                    }
                    else {
                        $obj->add_pre($out) if $out && $obj->{verbose};
                    }

                    require IPC::Open3;

                    my $just_made = Cpanel::cPAddons::Util::_create_my_cnf_if_needed( $obj->{'mysql_user'}, $obj->{'mysql_pass'} );
                    IPC::Open3::open3( \*MYSQL, \*MYRES, ">&STDERR", Cpanel::DbUtils::find_mysql(), '--defaults-file=' . $just_made, $obj->{'existing_mysql'} );
                    print MYSQL 'SHOW TABLES\G';
                    close MYSQL;
                    while (<MYRES>) {
                        chomp();
                        next unless m/Tables\_in\_/;
                        my ($tbl) = $_ =~ m/^Tables\_in\_\Q$obj->{'existing_mysql'}\E\:\s+(.*)/;
                        if ( $tbl =~ m/^$obj->{'table_prefix'}\_/ ) {
                            $tablesexist = 1;
                            last;
                        }
                    }
                    close MYRES;

                    unlink $just_made;

                    if ( !$tablesexist ) {
                        $obj->{'mysql'}->{$db}->{'_post'} = $obj->{'existing_mysql'};
                        $obj->{'mysql'}->{$db}->{'sqldb'} = $obj->{'existing_mysql'};
                    }
                    else {
                        require Capture::Tiny;
                        require Cpanel::SafeRun::API;
                        my ( $out, $err, $exit ) = Capture::Tiny::capture(
                            sub {
                                Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'DELUSER', $obj->{'mysql_user'} );
                            }
                        );
                        chomp($out);
                        chomp($err);
                        $obj->add_pre($out)                                                                                                                             if $out && $obj->{verbose};
                        $obj->add_pre( locale()->maketext( 'The system could not remove the database user: [_1]', Cpanel::Encoder::Tiny::safe_html_encode_str($err) ) ) if $err;
                        $obj->add_critical_error( locale()->maketext('Specify a different table prefix that is not in use in the selected database.') );
                        return 0;
                    }
                }
                else {
                    require Cpanel::Validate::DB::Name;
                    my $new_db = Cpanel::cPAddons::Util::find_unused_name( $Cpanel::user, $db, \&Cpanel::cPAddons::Util::_does_db_exist, $Cpanel::Validate::DB::Name::max_mysql_dbname_length );
                    $obj->{'new_mysql'}     = $new_db;
                    $obj->{'mysql_db_name'} = $new_db;

                    $obj->{'mysql'}->{$db}->{'_post'} = $new_db;

                    $obj->{'mysql'}->{$db}->{'sqldb'} = $obj->{'mysql'}->{$db}->{_post};
                    $obj->{'mysql'}->{$db}->{'sqldb'} = Cpanel::cPAddons::Util::_untaint( $obj->{'mysql'}->{$db}->{'sqldb'} );
                    require Capture::Tiny;
                    require Cpanel::SafeRun::API;
                    my $out = Capture::Tiny::capture_stdout(
                        sub {
                            Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'ADDDB', $obj->{'mysql'}->{$db}->{'sqldb'} );
                            Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'ADDUSERDB', $obj->{'mysql'}->{$db}->{'sqldb'}, $obj->{'mysql_user'}, 'ALL' );
                        }
                    );
                    chomp $out;
                    $obj->add_pre($out) if $out && $obj->{verbose};
                }

                $obj->{'mysql'}->{$db}->{'sqluser'}       = $obj->{'mysql_user'};
                $obj->{'mysql'}->{$db}->{'sqlpass'}       = $rndpass;
                $obj->{'mysql'}->{$db}->{'sqlhost'}       = `/usr/local/cpanel/bin/cpmysqlwrap GETHOST`;
                $obj->{'mysql'}->{$db}->{'mysql-version'} = $Cpanel::CONF{'mysql-version'};
            }
        }
    }
    return 1;
}

=head2 my_dropdbs(OBJ)

Drop the databases for this instance. This is used for uninstalls.

=cut

sub my_dropdbs {

    my $obj = shift;
    my $cnt = 1;

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };

    local $Cpanel::Parser::Vars::trap_defaultfh = 1;
    if (   $instance->{'table_prefix'}
        && $instance->{'existing_mysql'} ) {
        Cpanel::cPAddons::Util::_droptables(
            $instance->{'existing_mysql'},
            $instance->{'table_prefix'},
            $instance->{'mysql_user'},
            $instance->{'mysql_pass'},
        );
        my ($usr_ut) = $instance->{'mysql_user'} =~ m{ (.*) }xms;
        require Capture::Tiny;
        require Cpanel::SafeRun::API;
        my $out = Capture::Tiny::capture_stdout(
            sub {
                Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'DELUSER', $usr_ut );
            }
        );
        chomp $out;
        $obj->add_pre($out) if $out && $obj->{verbose};
    }
    else {
        require Capture::Tiny;
        require Cpanel::SafeRun::API;
        my $out = Capture::Tiny::capture_stdout(
            sub {
                for my $prefix ( keys %{ $instance->{'mysql'} } ) {
                    my $hasshared = 0;
                    my $db        = $instance->{'mysql'}->{$prefix}->{'sqldb'};
                    for my $install ( keys %{ $obj->{'installed'} } ) {
                        if ( $obj->{'installed'}->{$install}->{'existing_mysql'} eq $db ) {
                            $hasshared = 1;
                            last;
                        }
                    }
                    if ($hasshared) {
                        Cpanel::cPAddons::Util::_droptables(
                            $db,
                            $instance->{'table_prefix'},
                            $instance->{'mysql_user'},
                            $instance->{'mysql_pass'},
                        );
                    }
                    else {
                        print "\n" if $cnt == 1;
                        $cnt++;
                        my ($db_ut) = $db =~ m{ (.*) }xms;
                        Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'DELDB', $db_ut );
                        print "\n";
                        $obj->{'mysql_dropped'}->{$db} = 1;
                    }
                    my ($usr_ut) = $instance->{'mysql'}->{$prefix}->{'sqluser'} =~ m{ (.*) }xms;
                    Cpanel::SafeRun::API::html_encoded_api_safe_system( '/usr/local/cpanel/bin/cpmysqlwrap', 'DELUSER', $usr_ut );
                }
            }
        );
        chomp $out;
        $obj->add_pre($out) if $out and $obj->{verbose};
    }

    return 1;
}

=head2 my_dosql(OBJ, SQL, CHG_HR, USR, PSS)

Run SQL statements

=head3 Arguments

- OBJ - The Cpanel::cPAddons::Obj instance

- SQL - String - The path to a file containing the SQL statements

- CHG_HR - Hash ref - Contains a mapping of template keys that may be substituted in
the SQL statements to the corresponding values from the data structure

- USR - String - The database user

- PSS - String - The database password

=head3 Returns

True on success

False on failure

=cut

sub my_dosql {
    my ( $obj, $sql, $chg_hr, $usr, $pss ) = @_;
    $usr    = $obj->{'mysql_user'} if !$usr;
    $pss    = $obj->{'mysql_pass'} if !$pss;
    $chg_hr = {}                   if ref $chg_hr ne 'HASH';
    if ( -e $sql ) {
        if ( open my $sql_fh, '<', $sql ) {
            my $sql_data = do { local $/; <$sql_fh> };
            close $sql_fh;
            for ( keys %{$chg_hr} ) {

                # TODO: Consider replacing with _expand()
                $sql_data =~ s/\[\% \Q$_\E \%\]/$chg_hr->{$_}/g;
            }
            for ( keys %{$obj} ) {

                # TODO: Consider replacing with _expand()
                $sql_data =~ s/\[\% \Q$_\E \%\]/$obj->{$_}/g;
            }

            require IPC::Open3;

            my $just_made = Cpanel::cPAddons::Util::_create_my_cnf_if_needed( $usr, $pss );

            my $mysqlpid = IPC::Open3::open3( \*WMYSQL, \*RMYSQL, ">&STDERR", Cpanel::DbUtils::find_mysql(), '--defaults-file=' . $just_made );    # or die pipes not so valid
            close(RMYSQL);
            print WMYSQL $sql_data;
            close(WMYSQL);
            waitpid( $mysqlpid, 0 );

            unlink $just_made;
        }
        else {
            logger()->info("Could not open $sql: $!");
            return;
        }
    }

    return 1;
}

=head2 pg_createdbs()

Stub method for creating PostgreSQL databases for addons. We do not currently support PostgreSQL.

=head3 Returns

Always returns 1 because it is just a stub right now.

=cut

sub pg_createdbs { return 1; }

=head2 pg_dropdbs()

Stub method for removing PostgreSQL databases for addons. We do not currently support PostgreSQL.

=head3 Returns

Always returns 1 because it is just a stub right now.

=cut

sub pg_dropdbs { return 1; }

=head2 pg_dosql()

Stub method for executing SQL against PostgreSQL databases. We do not currently support PostgreSQL.

=head3 Returns

Always returns 1 because it is just a stub right now.

=cut

sub pg_dosql { return 1; }

=head2 process_install_scripts(OBJ, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

Process any additional install scripts specified by the addon in its metadata's run_scripts array. These scripts will eventually support multiple run modes, but currently only 'cli' is supported.

See process_run_scripts for details on arguments and return.

=cut

sub process_install_scripts {    ## no critic (ProhibitManyArgs) -- legacy code that is part of an interface
    my ( $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;
    my $run_scripts = $info_hr->{run_scripts_install};    # newer configs should use this
    if ( !$run_scripts ) {

        # run_script is the fall-back for compatibility with configs before the introduction of action specific run_scripts_*.
        $run_scripts = $info_hr->{run_scripts};
    }

    return 1 if !$run_scripts || ref $run_scripts ne 'ARRAY' || !@$run_scripts;
    return $obj->process_run_scripts( $run_scripts, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );
}

=head2 process_uninstall_scripts(OBJ, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

Process any additional uninstall scripts specified by the addon in its metadata's run_scripts array. These scripts will eventually support multiple run modes, but currently only 'cli' is supported.

See process_run_scripts for details on arguments and return.

=cut

sub process_uninstall_scripts {    ## no critic (ProhibitManyArgs) -- legacy code that is part of an interface
    my ( $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;
    my $run_scripts = $info_hr->{run_scripts_uninstall};    # Only available in 76+ uninstall scripts will not run in older versions
    return 1 if !$run_scripts || ref $run_scripts ne 'ARRAY' || !@$run_scripts;
    return $obj->process_run_scripts( $run_scripts, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );
}

=head2 process_run_scripts(OBJ, SCRIPTS, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

Process any additional scripts specified by the addon in its metadata's run_scripts array. These scripts will eventually support multiple run modes, but currently only 'cli' is supported.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

- SCRIPTS - Array Ref - List of scripts to run.

- INFO_HR - Hash Ref - The metadata provided by the addon. This is a duplicate of MODULE_DATA->{meta} but is required for historical reasons.

- INPUT_HR - Hash Ref - The form parameters from the client.

- SAFE_INPUT_HR - Hash Ref - HTML encoded version of the form parameters from the client.

- MODULE_DATA - Hash Ref - Additional information about a cPAddons module. Module Data is obtained via the Cpanel::cPAddons::Module::get_module_data() function based on a known module name, so there should normally be no need to construct it manually. See B<perldoc Cpanel::cPAddons::Module> for more information.

- ENV_HR - Hash Ref - See B<perldoc Cpanel::cPAddons> for more info on ENV_HR.

=head3 Returns

Returns 1 if there are no errors. Otherwise, returns undef and adds relevant errors to the OBJ.

=cut

sub process_run_scripts {    ## no critic (ProhibitManyArgs) -- legacy code that is part of an interface
    my ( $obj, $run_scripts, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;

    return 1 if !$run_scripts || ref $run_scripts ne 'ARRAY' || !@$run_scripts;

    # Setup the common data for the scripts
    my $data = {
        data        => $obj,
        form        => $input_hr,
        safe_form   => $safe_input_hr,
        environment => $env_hr,
        module      => $module_data,
    };

    for my $script (@$run_scripts) {
        if ( $script->{run} && $script->{run} eq 'cli' && $script->{name} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::cPAddons::Script::Runner::Cli');
            return if !Cpanel::cPAddons::Script::Runner::Cli::run( $script, $obj, $data );
        }
        else {
            $obj->add_error(
                locale()->maketext(
                    'Unrecognized run type “[_1]” for install script: [_2] Skipping …',
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $script->{run}  || '' ),
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $script->{name} || '' ),
                )
            );
            return;
        }
    }
    return 1;
}

=head2 procconfigfile(OBJ, FILES, MAP)

Processes config file templates in the FILES array ref, performing substitutions based on the information from MAP or OBJ.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

- FILES - Array Ref - List of config files to process.

- MAP - Hash Ref - Optional map of key-value pairs to use for substitutions. If this isn't provided, the values will be taken from OBJ.

=head3 Returns

Returns 1 if successful or if there is nothing to process. Returns undef if there are any errors.

=cut

sub procconfigfile {
    my ( $obj, $files, $map, $installdir ) = @_;

    $map        ||= {%$obj};                # unbless
    $installdir ||= $obj->{'installdir'};

    return 1 if !$files || ref $files ne 'ARRAY';

    # flatten sql hashref for mysql.dbname.sqldb type access
    if ( ref $map->{'mysql'} eq 'HASH' ) {
        for my $db ( keys %{ $map->{'mysql'} } ) {
            for ( keys %{ $map->{'mysql'}->{$db} } ) {
                $map->{"mysql.$db.$_"} = $map->{'mysql'}->{$db}->{$_};
            }
        }
    }

    if ( ref $map->{'postgre'} eq 'HASH' ) {
        for my $db ( keys %{ $map->{'postgre'} } ) {
            for ( keys %{ $map->{'postgre'}->{$db} } ) {
                $map->{"postgre.$db.$_"} = $map->{'postgre'}->{$db}->{$_};
            }
        }
    }

    # in-place edit
    my $inplace_error_count = 0;
    {

        local $^I              = '.bak';
        local @ARGV            = map { "$installdir/$_" } @{$files};
        local $SIG{'__WARN__'} = sub {

            $inplace_error_count++;
            logger()->info("Could not open $ARGV: $!");
            $obj->add_error(
                locale()->maketext(
                    'The system could not update the “[_1]” configuration file: “[_2]” You must update the file manually.',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($ARGV),
                    Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                )
            );
        };

        while (<ARGV>) {
            my $line = $_;
            for my $k ( keys %{$map} ) {

                # TODO: Consider replacing with _expand()
                $line =~ s/\[\% \Q$k\E \%\]/$map->{$k}/g;
            }
            print $line;
        }
    }
    unlink map { "$installdir/$_.bak" } @{$files};

    if ($inplace_error_count) {
        $obj->add_error( locale()->maketext('The system could not set the [asis,cPAddon’s] configuration. You must set the configuration manually.') );
        return;
    }

    return 1;
}

# TODO: Move to instance
sub _newregistry {
    my $obj = shift;
    my $num = 0;
    while ( -e "$Cpanel::homedir/.cpaddons/$obj->{'addon'}.$num.yaml" ) {
        $num++;
    }

    my $name = "$obj->{'addon'}.$num.yaml";
    my $file = "$Cpanel::homedir/.cpaddons/$name";

    if ( sysopen( my $nr_fh, $file, Fcntl::O_WRONLY | Fcntl::O_TRUNC | Fcntl::O_CREAT, 0600 ) ) {
        print {$nr_fh} '';    # necessary ?
        close $nr_fh;
        chmod 0600, $file;    # just in case
        $obj->{'registry'} = $name;
    }
    else {
        my $exception = $!;
        logger()->info("Error making registry file, $file: $!");
        $obj->add_error(
            locale()->maketext(
                'The system could not create the “[_1]” registry file: [_2]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($file),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            )
        );
        return 0;
    }
    return 1;
}

my @private_keys = qw(
  installed
  input_debug
  input_debug-0
  input_verbose
  input_verbose-0
  lang_obj
  license_html
  sorted_instances
  _self
  databases
  debug
  default_minimum_pass_length
  domain_to_docroot_map
  dophpasuserwarn
  dophpsuexecwarn
  dosuexecwarn
  extract_archives
  standard_install_fields
  lang
  minimum_pass_strength
  mysql_version
  notices
  phpsuexec
  postgre_version
  suexec
  verbose
  forced
  force_text
  force_text_length
  patch_test_output
  has_patch
  patch_failed
);

=head2 get_persistence_data(OBJ)

Filters the OBJ data to ensure that sensitive information is not stored on disk.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

=head3 Returns

A safe, filtered hash ref version of the OBJ that is ready to be stored on disk.

=cut

sub get_persistence_data {
    my ($obj) = @_;

    # NOTE: Because install and upgrade don't use the same object,
    # this $obj ref is not necessarly a Cpanel::cPAddons::Obj.
    # It should be treated like a hash for this method.

    # clean up any ./ installs
    $obj->{'installdir'}           =~ s/\.\/$//;
    $obj->{'url_to_install'}       =~ s/\/\.\///;
    $obj->{'url_to_install_admin'} =~ s/\/\.\///;

    my %safe_obj = %{$obj};    # make a copy of the obj hash.

    # Remove the private keys
    for my $private_key (@private_keys) {
        delete $safe_obj{$private_key};
    }

    for ( keys %safe_obj ) {
        delete $safe_obj{$_} if m/^form_/ || m/form$/ || /^input_/ || /^password/ || /apass/;
    }

    # Session that is safe to persist, cleaned up of any transient application data.
    return \%safe_obj;
}

=head2 register(OBJ)

Creates a registry file for the instance represented by OBJ.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

=head3 Returns

Returns 1 if successful or 0 if it fails.

=cut

sub register {
    my $obj = shift;
    if ( !defined $obj->{'registry'} || !$obj->{'registry'} ) {
        return 0 if !$obj->_newregistry();
    }

    my $persist = get_persistence_data($obj);

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} || '' };
    my $file     = $obj->{'workinginstall'} ? $instance->{'registry'} : $obj->{'registry'};

    if ( !Cpanel::cPAddons::Cache::write_cache( "$Cpanel::homedir/.cpaddons/$file", $persist ) ) {
        $obj->add_error(
            locale()->maketext(
                'The system could not register the [asis,cPAddon]: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'addon'} ),
            )
        );
        return 0;
    }
    return 1;
}

=head2 unregister(OBJ)

Removes a registry file for the instance represented by OBJ.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

=head3 Returns

Returns 1 if successful or 0 if it fails.

=cut

sub unregister {
    my $obj      = shift;
    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };
    my $path     = Cpanel::cPAddons::Util::_untaint("$Cpanel::homedir/.cpaddons/$instance->{'registry'}");
    if ( _exists($path) ) {
        if ( !_unlink($path) ) {
            my $exception = $!;
            $obj->add_error(
                locale()->maketext(
                    'The system could not remove the instance from the “[_1]” registry file: [_2]',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($path),
                    Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
                )
            );
            return 0;
        }
    }
    return 1;
}

sub remove_cron {
    my ($obj) = @_;

    my $instance = $obj->{'installed'}->{ $obj->{'workinginstall'} };
    if ( $instance->{'cron'} ) {
        chomp( my $to_be_removed = $instance->{'cron'} );

        if ($to_be_removed) {
            require Cpanel::TempFile;
            my $tmp_obj      = Cpanel::TempFile->new();
            my $tmp_filename = $tmp_obj->file();
            my @crontab_lines;
            require Cpanel::SafeRun::Errors;
            for ( Cpanel::SafeRun::Errors::saferunnoerror( 'crontab', '-l' ) ) {
                chomp;
                next if /^\Q$to_be_removed\E$/m;
                push @crontab_lines, "$_\n";
            }

            $obj->add_pre( locale->maketext('Removing cron jobs …') )
              if $obj->{verbose};

            if ( $tmp_filename && open my $cron_fh, '>', $tmp_filename ) {

                # TODO: More error handling
                print {$cron_fh} @crontab_lines;
                close $cron_fh;
                Cpanel::SafeRun::Errors::saferunnoerror( 'crontab', $tmp_filename );
                $obj->add_pre( locale->maketext('Done') ) if $obj->{verbose};
            }
            else {
                $obj->add_plain(
                    locale->maketext(
                        'The system could not remove the cron jobs entries: “[_1]” You must remove the entries manually.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($to_be_removed),
                    )
                );
                return 0;
            }
        }
    }
    return 1;
}

sub add_cron {
    my ( $obj, $info_hr ) = @_;

    if ( defined $info_hr->{'cron'} && $info_hr->{'cron'} ) {
        chomp $info_hr->{'cron'};
        if ( $info_hr->{'cron'} ) {
            require Cpanel::TempFile;
            my $tmp_obj      = Cpanel::TempFile->new();
            my $tmp_filename = $tmp_obj->file();

            $obj->{'cron'} = Cpanel::cPAddons::Transform::expand( $obj, $info_hr->{'cron'} );

            require Cpanel::SafeRun::Errors;
            my $cron = Cpanel::SafeRun::Errors::saferunnoerror( 'crontab', '-l' );
            $cron .= "\n$obj->{cron}\n";

            $obj->add_pre( locale()->maketext('Adding the application cron jobs …') )
              if $obj->{verbose};

            if ( $tmp_filename && open my $cron_fh, '>', $tmp_filename ) {

                # TODO: Add more error handing
                print {$cron_fh} $cron;
                close $cron_fh;
                Cpanel::SafeRun::Errors::saferunnoerror( 'crontab', $tmp_filename );
                $obj->add_pre( locale()->maketext('Done') ) if $obj->{verbose};
            }
            else {
                $obj->add_error(
                    locale()->maketext(
                        'The system could not create the cron job entries: “[_1]” You must create the entries manually.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($cron)
                    )
                );
                return 0;
            }
        }
    }
    return 1;
}

sub _do_phpsuexec_perms {
    my ($obj) = @_;

    if ( defined $obj->{'phpsuexec'} && $obj->{'phpsuexec'} eq 1 ) {
        if ( $obj->{'installdir'} && -d $obj->{'installdir'} ) {
            my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam( $obj->{'user'} ) )[ 2, 3 ];
            {
                Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
                local $SIG{'__WARN__'} = sub { Cpanel::Debug::log_warn(@_) };
                require Cpanel::SafetyBits;
                Cpanel::SafetyBits::safe_recchown( int($uid), int($gid), $obj->{'installdir'} );
                Cpanel::SafetyBits::safe_recchmod( 0755, $uid, $obj->{'installdir'} );
            }
        }
    }
    return 1;
}

sub _limit_security_rank {
    my $security_rank = shift;
    $security_rank = 0  if $security_rank !~ m/^\d+$/;
    $security_rank = 10 if $security_rank > 10;
    return $security_rank;
}

sub _get_contact_email {
    my ( $safe_input_hr, $instance ) = @_;

    my $contactemail = $safe_input_hr->{'email'} || $instance->{'email'};
    if ( !$contactemail ) {
        require Cpanel::Config::LoadCpUserFile;
        $contactemail = Cpanel::Config::LoadCpUserFile::load($Cpanel::user)->contact_emails_ar()->[0];
    }
    if ( $contactemail && $contactemail !~ m{ [@] }xms ) {
        $contactemail .= '@' . $Cpanel::CPDATA{'DNS'};
    }

    return $contactemail;
}

sub _render_template {
    my ( $path, $data ) = @_;
    my ( $ok, $output );

    my $args = { $data ? %$data : () };    # unwrap any objects
    $args->{template_file} = $path;
    $args->{print}         = 0;

    ( $ok, $output ) = Cpanel::Template::process_template( 'cpanel', $args );
    if ($ok) {
        print $$output;
        return 1;
    }

    $output = $$output if ref $output eq 'SCALAR';
    print $output;
    return 0;
}

sub _capture_template {
    my ( $path, $data ) = @_;
    my ( $ok, $output );

    my $args = { $data ? %$data : () };    # unwrap any objects
    $args->{template_file} = $path;
    $args->{print}         = 0;

    ( $ok, $output ) = Cpanel::Template::process_template( 'cpanel', $args, \$output );
    return $output;
}

sub _build_archive_list {
    my $obj       = shift;
    my $module_hr = shift;
    my $info_hr   = $module_hr->{meta};

    my $path = "$Cpanel::cPAddons::Globals::Static::base/$module_hr->{'rel_folder'}";

    if ( $info_hr->{extract_archives} && ref $info_hr->{extract_archives} eq 'ARRAY' ) {
        $obj->{extract_archives} = [ map { "$path/$_" } @{ $info_hr->{extract_archives} } ];
    }
    elsif ( $info_hr->{extract_archives} && !ref( $info_hr->{extract_archives} ) ) {
        $obj->{extract_archives} = ["$path/$info_hr->{extract_archives}"];
    }
    else {
        # Legacy support to look for a <version>.tar.gz
        $obj->{extract_archives} = ["$path/$info_hr->{'version'}.tar.gz"];
    }

    return 1;
}

sub process_chmod {
    my $obj     = shift;
    my $info_hr = shift;

    return 1 if ( !$info_hr->{'chmod'} || ref $info_hr->{'chmod'} ne 'HASH' );

    my @sort =
      ref $info_hr->{'chmod_order'} eq 'ARRAY'
      ? @{ $info_hr->{'chmod_order'} }
      : sort keys %{ $info_hr->{'chmod'} };
    for (@sort) {
        if ( $info_hr->{'chmod_recursive'} ) {
            require Cpanel::SafetyBits;
            Cpanel::SafetyBits::safe_recchmod( $_, $obj->{'user'}, @{ $info_hr->{'chmod'}->{$_} } ) and return 0;
        }
        else {
            if ( !_chmod( oct($_), @{ $info_hr->{'chmod'}->{$_} } ) ) {
                $obj->add_error(
                    locale()->maketext(
                        'The system could not chmod the “[_1]” file: [_2]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($_),
                        Cpanel::Encoder::Tiny::safe_html_encode_str($!)
                    )
                );
                return 0;
            }
        }
    }

    return 1;
}

sub _chmod {
    my ( $mode, @targets ) = @_;
    return chmod $mode, @targets;
}

sub process_chgrp {
    my $obj     = shift;
    my $info_hr = shift;

    return 1 if ( !$info_hr->{'chgrp'} );

    my ( undef, undef, $uid, $gid ) = Cpanel::PwCache::getpwnam( $obj->{'user'} );

    require Cpanel::SafeRun::Errors;
    Cpanel::SafeRun::Errors::saferunnoerror( 'chgrp', '-R', scalar( getgrgid($gid) ), '.' );
    return $? ? 0 : 1;
}

=head2 secure_admin_area(OBJ, INFO_HR, INPUT_HR)

Creates an .htaccess file to password protect the admin area if the path to one is specified.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

- INFO_HR - Hash Ref - The metadata provided by the addon.

=head3 Returns

Returns 1 if successful or if there is nothing to process. If there are any errors, it returns undef and adds errors to the OBJ.

=cut

sub secure_admin_area {
    my ( $obj, $info_hr );

    return 1 if !$obj->{'username'} || !$obj->{'password'} || !$info_hr->{'adminarea_path'};

    # Add directory protection to the admin area
    $obj->add_pre(
        locale()->maketext(
            'Protecting [_1] directory …',
            Cpanel::Encoder::Tiny::safe_html_encode_str( $info_hr->{'adminarea_path'} )
        )
    ) if $obj->{verbose};

    my $path = "$obj->{'installdir'}/$info_hr->{'adminarea_path'}";
    require Cpanel::Htaccess;
    Cpanel::Htaccess::set_protect( $path, 1, "$info_hr->{adminarea_name} Admin" );
    Cpanel::Htaccess::set_pass( $path, $obj->{'username'}, $obj->{'password'} );
    $obj->add_pre( locale()->maketext('Done') ) if $obj->{verbose};

    if ( !chdir $obj->{'installdir'} ) {
        logger()->info("Could not change back into install dir ($obj->{'installdir'}): $!");
        $obj->add_error(
            locale->maketext(
                "The system could not open the install directory [_1]: [_2]",
                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'installdir'} ),
                Cpanel::Encoder::Tiny::safe_html_encode_str($!),
            )
        );
        return;
    }

    return 1;
}

=head2 untar_archives(OBJ, INFO_HR)

Extract the tarball for an addon. This is used for installs.

=head3 Arguments

- OBJ - The Cpanel::cPAddons::Obj instance

- INFO_HR - Hash ref - Specifically, this is used to find 'untar_params', which is an optional
array ref expanded into extra arguments for the tar command.

=head3 Returns

True on success

False on failure

=cut

sub untar_archives {
    my $obj     = shift;
    my $info_hr = shift;

    # Extract the archives to the install directory
    # REQUIRED: All addons must have at least one archive to extract
    my $tar_files = $obj->{extract_archives};

    if ( !$tar_files || ref $tar_files ne 'ARRAY' ) {
        $obj->add_critical_error( locale()->maketext("The system could not extract the [asis,cPAddon’s] archive. The archive is either invalid or incomplete. Contact the [asis,cPAddon’s] distributor for assistance.") );
        return;
    }

    my $tar = Cpanel::Binaries::path('tar');

    for my $tar_file (@$tar_files) {
        if ( -e $tar_file ) {
            $obj->add_pre(
                locale()->maketext(
                    'Extracting [_1] into [_2] …',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($tar_file),
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{installpath} ),
                )
            ) if $obj->{verbose};

            # Setup the tar argument list
            my @args;
            push @args, @{ $info_hr->{untar_params} }
              if $info_hr->{untar_params} && ref $info_hr->{untar_params} eq 'ARRAY';
            push @args, ( '-xzf', $tar_file );

            require Cpanel::SafeRun::Errors;
            Cpanel::SafeRun::Errors::saferunnoerror( $tar, @args );
            if ( $? != 0 ) {
                $obj->add_critical_error( locale()->maketext( "The system could not [asis,untar] the “[_1]” file.", Cpanel::Encoder::Tiny::safe_html_encode_str($tar_file) ) );

                # Something failed so try to cleanup
                if ( $obj->{'installpath'} ne './' ) {
                    if ( !chdir $obj->{'public_html'} ) {
                        logger()->info("Could not change into directory public_html: $!");
                        logger()->info("$obj->{'installpath'} will need cleaned up manually.");

                        $obj->add_error(
                            locale()->maketext(
                                "The system could not open the public_html directory: “[_1]” You must manually clean up the “[_2]” directory.",
                                Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'installpath'} ),
                            )
                        );
                        return;
                    }
                    if ( !Cpanel::SafeDir::RM::safermdir( $obj->{'installpath'} ) ) {
                        $obj->add_error(
                            locale()->maketext(
                                "The system could not delete the “[_1]” directory: [_2]",
                                Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{'installpath'} ),
                                Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                            )
                        );
                    }
                }
                else {
                    chomp( my @possible_stragglers = `$tar tzf $tar_file` );
                    for my $path (@possible_stragglers) {
                        next if $path eq './' || $path eq '.' || $path eq '/';
                        if ( -l $path || -e _ ) {
                            if ( !unlink $path ) {
                                $obj->add_error(
                                    locale()->maketext(
                                        "The system could not remove the “[_1]” file: [_2]. You must remove the directory manually.",
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($path),
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                                    )
                                );
                            }
                        }
                        elsif ( -d _ ) {
                            if ( !Cpanel::SafeDir::RM::safermdir($path) ) {
                                $obj->add_error(
                                    locale()->maketext(
                                        "The system could not remove the “[_1]” directory: [_2]. You must remove the directory manually.",
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($path),
                                        Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                                    )
                                );
                            }
                        }
                    }

                    if ( !chdir $obj->{'public_html'} ) {
                        logger()->info("Could not change into public_html directory: $!");
                        $obj->add_error(
                            locale()->maketext(
                                "The system could not open the “[_1]” directory: [_2]",
                                'public_html',
                                Cpanel::Encoder::Tiny::safe_html_encode_str($!)
                            )
                        );
                        return;
                    }
                }

                return;
            }
        }
        else {
            $obj->add_critical_error(
                locale()->maketext(
                    'The system could not locate the “[_1]” archive for the “[_2]” [asis,cPAddon].',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($tar_file),
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{addon} ),
                )
            );
            return;
        }
    }
    return 1;
}

sub process_import_file {
    my ( $obj, $info_hr, $input_hr ) = @_;

    if ( defined $input_hr->{'import_file'}
        && $input_hr->{'import_file'} ) {
        if ( -r $input_hr->{'import_file'} ) {
            $obj->add_pre(
                locale()->maketext(
                    "Starting import of “[_1]” …",
                    Cpanel::Encoder::Tiny::safe_html_encode_str( $input_hr->{'import_file'} )
                )
            ) if $obj->{verbose};

            require Cpanel::SafeRun::Errors;
            Cpanel::SafeRun::Errors::saferunnoerror( Cpanel::Binaries::path('tar'), "xzf", "$input_hr->{'import_file'}" );
            if ( $? != 0 ) {
                $obj->add_warning(
                    locale()->maketext(
                        'The system could not [asis,untar] the “[_1]” file. You must [asis,untar] the file manually.',
                        Cpanel::Encoder::Tiny::safe_html_encode_str( $input_hr->{'import_file'} )
                    )
                );
                return;
            }

            if ( -e "$input_hr->{'import_file'}.sql" ) {
                my $import_sql = Cpanel::cPAddons::Util::_untaint("$input_hr->{'import_file'}.sql");
                if ( $obj->my_dosql($import_sql) ) {
                    if ( !unlink $import_sql ) {
                        $obj->add_error(
                            locale()->maketext(
                                'The system could not remove the “[_1]” file: “[_2]” You must remove the file manually.',
                                Cpanel::Encoder::Tiny::safe_html_encode_str($import_sql), $!
                            )
                        );
                    }
                }
                else {
                    $obj->add_warning(
                        locale()->maketext(
                            'The system could not run the “[_1]” SQL file. You must run the file manually.',
                            Cpanel::Encoder::Tiny::safe_html_encode_str($import_sql), $!
                        )
                    );
                    return;
                }
            }
            $obj->add_pre( locale()->maketext('Import Complete') ) if $obj->{verbose};
            return 1;
        }
        else {
            $obj->add_error( locale()->maketext('You specified an invalid import file.') );
            return;
        }
    }
    return;
}

sub check_perl_modules {
    my $obj     = shift;
    my $info_hr = shift;

    if ( defined $info_hr->{'perl_module'}
        && ref $info_hr->{'perl_module'} eq 'HASH' ) {
        for my $name ( keys %{ $info_hr->{'perl_module'} } ) {
            my $missing = `perl -e 'use $_ $info_hr->{'perl_module'}->{$name};' 2>&1`;
            if ($missing) {
                $obj->add_warning(
                    locale()->maketext(
                        "For your installation to function properly, your hosting provider must install the [_1] [_2] [asis,Perl] module.",
                        $name, $info_hr->{'perl_module'}->{$name}
                    )
                );
            }
        }
    }
    return 1;
}

sub create_dbs {
    my $obj     = shift;
    my $info_hr = shift;

    if (   !$obj->my_createdbs( $info_hr->{'mysql'} )
        || !$obj->pg_createdbs( $info_hr->{'postgre'} ) ) {
        return;
    }

    # add my_sql_replace dbs
    for ( keys %{ $obj->{'mysql'} } ) {
        $obj->{$_} = $obj->{'mysql'}->{$_}->{'sqldb'};
    }

    # TODO: do same for pg when added

    # flatten sql hashref for mysql.dbname.sqldb type access
    for my $db ( keys %{ $obj->{'mysql'} } ) {
        for ( keys %{ $obj->{'mysql'}->{$db} } ) {
            $obj->{"mysql.$db.$_"} = $obj->{'mysql'}->{$db}->{$_};
        }
    }
    for my $db ( keys %{ $obj->{'postgre'} } ) {
        for ( keys %{ $obj->{'postgre'}->{$db} } ) {
            $obj->{"postgre.$db.$_"} = $obj->{'postgre'}->{$db}->{$_};
        }
    }

    my $sql_file = "$Cpanel::cPAddons::Globals::Static::base/$obj->{'addon_path'}/$info_hr->{'version'}";
    if ( -e "$sql_file.mysql" && !$obj->my_dosql("$sql_file.mysql") ) {
        $obj->add_error( locale()->maketext( 'The system cannot process the [asis,MySQL] file: [_1]', "$sql_file.mysql" ) );
        return;
    }

    if ( -e "$sql_file.postgre" && !$obj->pg_dosql("$sql_file.postgre") ) {
        $obj->add_error( locale()->maketext( 'The system cannot process the [asis,MySQL] file: [_1]', "$sql_file.postgre" ) );
        return;
    }

    return 1;
}

=head2 process_config_file(OBJ, INFO_HR)

Processes config file templates in the config_files array ref inside of INFO_HR, performing substitutions based on the information in OBJ. This method is a wrapper around procconfigfile() and the preferred method going forward.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

- INFO_HR - Hash Ref - The metadata provided by the addon.

=head3 Returns

Returns 1 if successful or if there is nothing to process. Returns undef if there are any errors.

=cut

sub process_config_file {
    my $obj     = shift;
    my $info_hr = shift;

    # Pipeline wrapper since we have to preserve procconfigfile as it is
    # since it may be called in the wild and by other customer installers.
    return $obj->procconfigfile( $info_hr->{'config_files'} );
}

our $available_policies = {
    process_config_file_permissions => \&Cpanel::cPAddons::Security::process_config_file_permissions,
    process_file_permissions        => \&Cpanel::cPAddons::Security::process_file_permissions,

    # NOTE: Add other security policies and fixers here.
};

=head2 process_security_check(OBJ, INFO_HR, INPUT_HR, SAFE_INPUT_HR, MODULE_DATA, ENV_HR)

Process any security policies defined by the addon's module in the security_policies array. If an addon-defined policy method fails, it should return a falsy value for process_security_check() to recognize the failure.

=head3 Arguments

- OBJ - Object - The Cpanel::cPAddons::Obj instance.

- INFO_HR - Hash Ref - The metadata provided by the addon. This is a duplicate of MODULE_DATA->{meta} but is required for historical reasons.

- INPUT_HR - Hash Ref - The form parameters from the client.

- SAFE_INPUT_HR - Hash Ref - HTML encoded version of the form parameters from the client.

- MODULE_DATA - Hash Ref - Additional information about a cPAddons module. Module Data is obtained via the Cpanel::cPAddons::Module::get_module_data() function based on a known module name, so there should normally be no need to construct it manually. See B<perldoc Cpanel::cPAddons::Module> for more information.

- ENV_HR - Hash Ref - See B<perldoc Cpanel::cPAddons> for more info on ENV_HR.

=head3 Returns

This method always returns 1 unless there is an exception thrown in the security policy method. Errors are added to the OBJ instance to notify users.

=cut

sub process_security_check {    ## no critic (ProhibitManyArgs) -- legacy code
    my ( $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr ) = @_;

    if ( $info_hr->{security_policies} && ref $info_hr->{security_policies} eq 'ARRAY' ) {
        $obj->{security_policies} = {};

        for my $policy ( @{ $info_hr->{security_policies} } ) {
            if ( $policy->{name} eq 'process_config_file_permissions' ) {
                $obj->add_pre(
                    $policy->{description},
                ) if $obj->{verbose} and $policy->{description};
            }

            my $method = $policy->{name};
            if ( !$method ) {
                $obj->add_error( locale()->maketext('The security measure is not configured in the module meta-data. It requires a name property.') );
            }
            elsif ( !$available_policies->{$method} ) {
                $obj->add_error( locale()->maketext( 'The “[_1]” security measure is not available.', $method ) );
            }
            else {
                my $status = $available_policies->{$method}->( $policy, $obj, $info_hr, $input_hr, $safe_input_hr, $module_data, $env_hr );
                last if !$status;    # Measures should return false if the process loop should end after a failure.
            }
        }
    }

    return 1;
}

1;
