package Cpanel::cPAddons;

# cpanel - Cpanel/cPAddons.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

##no critic(RequireUseWarnings) -- This is legacy code that relies on the ability to do string comparisons on undef values.

use Try::Tiny;

use Cpanel                            ();
use Cpanel::cPAddons::Actions         ();
use Cpanel::cPAddons::File::Perms     ();
use Cpanel::cPAddons::Globals         ();
use Cpanel::cPAddons::Globals::Static ();
use Cpanel::cPAddons::Instances       ();
use Cpanel::cPAddons::Module          ();
use Cpanel::cPAddons::Notices         ();
use Cpanel::cPAddons::Obj             ();
use Cpanel::cPAddons::Util            ();
use Cpanel::Config::LoadCpConf        ();
use Cpanel::Server::Type              ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::FHTrap                    ();
use Cpanel::MD5                       ();
use Cpanel::PasswdStrength::Check     ();
use Cpanel::PwCache                   ();
use Cpanel::Template                  ();
use Cpanel::OS                        ();

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Locale ();

use Cpanel::Imports;

our $VERSION = '0.9.8';

# Deprecated
# Retained for backward compatibility with callers that rely on the exported cPAddons_init function
sub cPAddons_init {
    my @args = @_;
    Cpanel::cPAddons::Globals::init_globals(@args);
}

sub proc_keys_named_after_version {
    my ( $hr, $pkg ) = @_;
    $pkg = ( caller() )[0] if !$pkg;

    my $relpath = "$pkg.pm";
    $relpath =~ s{::}{/}g;
    if ( !exists $INC{$relpath} ) {
        logger()->info("Package, $relpath, not in INC, skipping");
        Cpanel::cPAddons::Notices::singleton()->add_error(
            locale()->maketext(
                'The system could not locate the “[_1]” package in the [asis,Perl INC] path.',
                Cpanel::Encoder::Tiny::safe_html_encode_str($relpath),
            )
        );
        return;
    }

    my $path = $INC{$relpath};
    $path =~ s{ [.] pm \z }{}xms;

    my $dir = $path . '/keys_named_after_version';
    return if !-d $dir;

    my @files;
    if ( opendir my $dh, $dir ) {
        @files = grep !/ \A [.]+ \z /xms, readdir($dh);
        closedir $dh;
    }

    for my $file (@files) {
        next if exists $hr->{$file};
        my $loaded_hr    = {};
        my $path_to_file = "$dir/$file";
        require Cpanel::DataStore;
        if ( Cpanel::DataStore::load_ref( $path_to_file, $loaded_hr ) ) {
            $hr->{$file} = $loaded_hr;
        }
        else {
            logger()->info("Could not load the file: $path_to_file.");
            Cpanel::cPAddons::Notices::singleton()->add_error(
                locale()->maketext(
                    'The system could not load the file: [_1]',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($path_to_file),
                )
            );
        }
    }
    return;
}

sub _handle_checked {
    Cpanel::cPAddons::Globals::init_globals();
    my $vendor_name = $Cpanel::cPAddons::Globals::pal;
    my $base_dir    = $Cpanel::cPAddons::Globals::Static::base;
    my $pmfile      = sprintf( "%s/cPAddonsMD5/%s.pm", $base_dir, $vendor_name );

    my $current_md5  = Cpanel::MD5::getmd5sum($pmfile);
    my $expected_md5 = $Cpanel::cPAddons::Globals::approved_vendors{$vendor_name}->{'palmd5'};

    return _render_template(
        'addoncgi/views/check.tt',
        {
            vendor => {
                name => $vendor_name,
            },
            current_md5  => $current_md5,
            expected_md5 => $expected_md5,
        }
    );
}

sub _build_environment {
    my ( $called_from_root, $input_hr ) = @_;
    require Cpanel::cPAddons::Moderation;
    my $moderated_info = Cpanel::cPAddons::Moderation::get_moderated_modules();

    my ($can_add_subdomains) = Cpanel::cPAddons::Util::check_max_subdomains();
    my $cpconf_ref = %Cpanel::CONF ? \%Cpanel::CONF : Cpanel::Config::LoadCpConf::loadcpconf();

    return {
        script_name        => $ENV{'SCRIPT_NAME'},
        called_from_root   => $called_from_root,
        verbose            => $input_hr ? ( $input_hr->{verbose} ? 1 : 0 ) : 0,
        debug              => $input_hr ? ( $input_hr->{debug}   ? 1 : 0 ) : 0,
        moderated          => $moderated_info->{moderated} || {},
        script_run_as_user => Cpanel::cPAddons::File::Perms::runs_as_user(),
        mysql_version      => $cpconf_ref->{'mysql-version'},
        lowest_allowed     => 0,
        can_add_subdomains => $can_add_subdomains ? 1 : 0,
        domains            => {
            primary => "$Cpanel::CPDATA{'DNS'}",
        },
    };
}

sub cPAddons_mainpg {
    my $input_hr = shift;
    my $opts     = shift || {};

    return if _exit_early();

    no warnings 'once';
    local $Cpanel::IxHash::Modify = 'none';

# If we are calling via API we need to read the form data directly
# Example: https://mydomain.tld:2083/cpsess3404393075/json-api/cpanel?cpanel_jsonapi_user=myuser&cpanel_jsonapi_apiversion=1&cpanel_jsonapi_module=cPAddons&cpanel_jsonapi_func=mainpg&addon=cPanel%3A%3ABlogs%3A%3AWordPressX&action=install&debug=0&verbose=0&oneclick=1&subdomain=myuser.org&installdir=wordpress&auser=&apass=&apass2=&email=user%40cpanel.net&1blog_name=My+WordPress+Website&2blog_description=Just+another+WordPress+site&table_prefix=wp&existing_mysql=
    $input_hr ||= \%Cpanel::FORM;

    my $called_from_root = $opts->{called_from_root} || 0;
    if ( $> == 0 ) {
        my $user = $ENV{'cpasuser'};
        return unless defined $user;
        return if $user eq 'root';
        return if exists $input_hr->{'asuser'} && $input_hr->{'asuser'} ne $user;
    }

=head1 ENV_HR

env_hr is a hash ref that contains the following data:

- script_name - String - Same as the SCRIPT_NAME environment variable

- called_from_root - Boolean - Indicates whether the operation is being performed by root. This may alter
the behavior of other functions that get called.

- verbose - Boolean - Whether to provide additional diagnostic info.

- debug - Boolean - Whether to provide more detailed debugging info.

=cut

    my $env_hr = _build_environment( $called_from_root, $input_hr );

    _set_user($>);

    return if $> == 0;

    delete $input_hr->{'asuser'};    # just to be safe

    if ( $input_hr->{'check'} ) {
        return _handle_checked();
    }

    my $safe_input_hr = Cpanel::cPAddons::Util::_cleanse_input_hr($input_hr);

    my $notices = Cpanel::cPAddons::Notices::singleton();

    my $mod = $input_hr->{'addon'};
    if ($mod) {
        my $module_data = Cpanel::cPAddons::Module::get_module_data($mod);
        if ( $module_data && -e $module_data->{fullpath} ) {
            _handle_module( $module_data, $input_hr, $safe_input_hr, $env_hr );
        }
        else {
            $notices->add_critical_error( locale()->maketext('The [asis,cPAddon] that you requested does not contain the required metadata file.') );
            _listallmods(
                environment => $env_hr,
                notices     => $notices,
            );
        }
    }
    elsif ( $input_hr->{action} eq 'notify' ) {
        return _handle_toggle_notify( $input_hr, $safe_input_hr, $env_hr );
    }
    else {
        return _listallmods( environment => $env_hr, notices => $notices );
    }

    return 1;
}

sub _listallmods {
    my %args = @_;

    my $all_addons = $Cpanel::cPAddons::Class::SINGLETON->list_available_modules();
    my $addon_list = _gather_addon_list( $all_addons, $args{environment} );

    _handle_main_header( $all_addons, $addon_list, $args{notices}, $args{environment} );
    _display_addon_list( $all_addons, $addon_list );

    return;
}

sub _handle_main_header {
    my ( $all_addons, $addon_list, $notices, $environment ) = @_;
    my $categories = scalar keys %$addon_list;

    my $have_both_addons    = ( $all_addons->{'Blogs'}{'cPanel::Blogs::WordPress'} && $all_addons->{'Blogs'}{'cPanel::Blogs::WordPressX'} ) ? 1 : 0;
    my $legacy_addon_listed = ( $addon_list->{'Blogs'}                             && $addon_list->{'Blogs'}{'cPanel::Blogs::WordPress'} );

    if ( $have_both_addons && $legacy_addon_listed ) {
        $notices->add_info( locale()->maketext('[asis,WordPress (legacy)] does not support the [asis,WordPress] self-update system and does not allow new installations. [asis,cPanel], [asis,L.L.C.] will remove [asis,WordPress (legacy)] in a future version of [asis,cPanel] [output,amp] [asis,WHM].') );
    }

    require Cpanel::cPAddons::Notifications;
    my $template_data = {
        version  => $VERSION,
        settings => {
            cpaddons_notify_users => Cpanel::cPAddons::Notifications::get_setting(),
        },
        notifications => {
            enabled => Cpanel::cPAddons::Notifications::are_notifications_enabled(),
        },
        has_categories => $categories > 0 ? 1 : 0,
        notices        => $notices,
        environment    => $environment,
    };

    _render_template( 'addoncgi/views/list.tt', $template_data );

    return;
}

sub _gather_addon_list {

    # TODO: Extract into template
    my $all_addons        = shift;
    my $environment       = shift;
    my $approved_addons   = $Cpanel::cPAddons::Class::SINGLETON->get_approved_addons();
    my $deprecated_addons = $Cpanel::cPAddons::Class::SINGLETON->get_deprecated_addons();

    my @instances;
    if ( opendir( my $instances_dh, "$Cpanel::homedir/.cpaddons/" ) ) {
        @instances = grep { !/^moderation$/ && !/\,v$/ && !/^\./ } readdir $instances_dh;
        closedir $instances_dh;
    }

    my %installed_count_by_category;
    my %installable_count_by_category;

    my %entries;

    for my $category ( sort keys %$all_addons ) {
        my $addons_under_category_count = scalar keys %{ $all_addons->{$category} };
        $installable_count_by_category{$category} = 0;

        for my $package_name ( sort keys %{ $all_addons->{$category} } ) {

            my ($vendor_name)    = $package_name =~ m/^(\w+)/;
            my ($category_addon) = $package_name =~ m/^\w+\:\:(.*)/;

            my $duplicate_module_count_under_different_vendors = 0;
            for my $vendor ( keys %Cpanel::cPAddons::Globals::approved_vendors ) {
                $duplicate_module_count_under_different_vendors++
                  if exists $all_addons->{$category}{"$vendor\:\:$category_addon"};
            }

            # Only show the vendor if there is more than
            # one addon with matching category/addon name
            # but distributed by different vendors.
            my $vendor_display_per_addon =
              $duplicate_module_count_under_different_vendors >= 2
              ? locale()->fetch( q{ (from [_1])}, $vendor_name )
              : '';

            my @installed_instances_of_this_addon = grep { /^\Q$package_name\E\.\d+/ } @instances;
            my $installed_instances               = @installed_instances_of_this_addon;
            $installed_count_by_category{$category} += $installed_instances;

            # Do not display disabled or deprecated addons unless they have
            # at least one installed. Disabled here means it was unchecked
            # via the WHM Install Site Software interface but not completely
            # removed from the file system. (The .pm file is still in the
            # /usr/local/cpanel/cpaddons/<vendor>/<category>/ folder.)
            next if $installed_instances < 1 && ( !$approved_addons->{$package_name} || $deprecated_addons->{$package_name} );

            $installable_count_by_category{$category}++;

            my $desc = $Cpanel::cPAddons::Globals::cpanelincluded{$vendor_name}->{$package_name}->{'desc'};
            my $what = Cpanel::Encoder::Tiny::safe_html_encode_str($desc)
              || locale()->fetch('No Description Provided');
            my $url = _to_uri( $environment, "addon=$package_name" );

            $entries{$category}{$package_name} = {
                url                      => $url,
                pretty_name              => $all_addons->{$category}->{$package_name},
                vendor_display_per_addon => $vendor_display_per_addon,
                installed_instances      => $installed_instances,
                what                     => $what,
            };

        }
    }

    return \%entries;
}

sub _display_addon_list {
    my ( $all_addons, $addon_list ) = @_;

    my $template_data = {
        addon_list => $addon_list,
    };

    _render_template( 'addoncgi/views/addon_list.tt', $template_data );

    return;
}

sub load_cpaddon_feature_descs {
    return $Cpanel::cPAddons::Class::SINGLETON->load_cpaddon_feature_descs();
}

sub load_cpaddon_feature_names {
    return $Cpanel::cPAddons::Class::SINGLETON->load_cpaddon_feature_names();
}

sub _handle_module {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    if ( $input_hr->{'action'} eq 'install' ) {
        my $is_moderated = _is_module_moderated( $module_data->{name} );
        if ( $is_moderated && !$env_hr->{called_from_root} ) {
            $module_data->{is_moderated} = 1;
            my $approved = _is_module_approved( $module_data->{name} );
            if ( !$approved ) {
                $input_hr->{'action'} = 'moderate';
            }
        }
    }

    if ( !$input_hr->{'action'} ) {
        return _handle_manager( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
    elsif ( $input_hr->{'action'} eq 'moderate' ) {
        return _handle_moderation( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
    elsif ( $input_hr->{'action'} eq 'sendmodreq' ) {
        return _handle_send_moderation_request( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
    elsif ( $input_hr->{'action'} eq 'install' ) {
        return _handle_install( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
    elsif ( $input_hr->{'action'} eq 'uninstall' ) {
        return _handle_uninstall( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
    elsif ( $input_hr->{'action'} eq 'upgrade' ) {
        return _handle_upgrade( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
    else {
        warn "should add condition for action $input_hr->{'action'}";    # temporary
        return _handle_other( $module_data, $input_hr, $safe_input_hr, $env_hr );
    }
}

sub _handle_manager {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    my $pal = $Cpanel::cPAddons::Globals::pal;

    my $template_data = {
        safeform    => $safe_input_hr,
        form        => $input_hr,
        environment => $env_hr,
        vendor      => {
            name => $pal,
            %{ $Cpanel::cPAddons::Globals::approved_vendors{$pal} }
        },
        module   => $module_data,
        settings => {
            no_modified_cpanel    => Cpanel::cPAddons::Util::get_no_modified_cpanel_addons_setting() ? 1 : 0,
            no_3rd_party          => Cpanel::cPAddons::Util::get_no_3rd_party_addons_setting()       ? 1 : 0,
            min_password_strength => Cpanel::PasswdStrength::Check::get_required_strength('cpaddons'),
        },
        actionlessuri => _get_actionless_uri($safe_input_hr),
        data          => {
            notices => Cpanel::cPAddons::Notices::singleton(),
        },
    };
    return _render_manager_ui($template_data);
}

sub _handle_toggle_notify {
    my ( $input_hr, $safe_input_hr, $env_hr ) = @_;

    require Cpanel::cPAddons::Notifications;
    my $response;
    if ( $input_hr->{'on'} ) {
        $response = Cpanel::cPAddons::Notifications::enable_notifications();
    }
    elsif ( !$input_hr->{'on'} ) {
        $response = Cpanel::cPAddons::Notifications::disable_notifications();
    }

    $response->{actionlessuri} = _get_actionless_uri($safe_input_hr);
    $response->{environment}   = $env_hr;

    return _render_template( 'addoncgi/views/notifications.tt', $response );
}

sub _handle_install {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    my $response = Cpanel::cPAddons::Actions::handle_install( $module_data, $input_hr, $safe_input_hr, $env_hr );

    my $data = {
        environment   => $env_hr,
        module        => $module_data,
        form          => $input_hr,
        data          => $response,
        form          => $input_hr,
        actionlessuri => _get_actionless_uri($safe_input_hr),
    };

    return _render_template( 'addoncgi/views/action_install.tt', $data );
}

sub _handle_uninstall {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    if ( !$input_hr->{'verified'} && !$env_hr->{called_from_root} ) {
        my $install = Cpanel::cPAddons::Instances::get_instance( $input_hr->{'workinginstall'} );
        my $domain  = $install->{url};
        $domain =~ s/\/$//;
        my $data = {
            environment     => $env_hr,
            module          => $module_data,
            form            => $input_hr,
            working_install => $input_hr->{'workinginstall'},
            data            => {
                instance_url => $domain,
            },
            actionlessuri => _get_actionless_uri($safe_input_hr),
        };

        return _render_template( 'addoncgi/views/verify_uninstall.tt', $data );
    }
    else {

        my $response = Cpanel::cPAddons::Actions::handle_uninstall( $module_data, $input_hr, $safe_input_hr, $env_hr );
        my $data     = {
            environment   => $env_hr,
            module        => $module_data,
            form          => $input_hr,
            data          => $response,
            actionlessuri => _get_actionless_uri($safe_input_hr),
        };

        return _render_template( 'addoncgi/views/action_uninstall.tt', $data );
    }
}

sub _handle_upgrade {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    if ( !$input_hr->{'verified'} && !$env_hr->{called_from_root} ) {
        my $install = Cpanel::cPAddons::Instances::get_instance( $input_hr->{'workinginstall'} );
        my $data    = {
            environment     => $env_hr,
            module          => $module_data,
            form            => $input_hr,
            working_install => $input_hr->{'workinginstall'},
            data            => {
                instance_url => $install->{url},
            },
            actionlessuri => _get_actionless_uri($safe_input_hr),
        };
        return _render_template( 'addoncgi/views/verify_upgrade.tt', $data );
    }
    else {
        my $response = Cpanel::cPAddons::Actions::handle_upgrade( $module_data, $input_hr, $safe_input_hr, $env_hr );
        my $data     = {
            environment   => $env_hr,
            module        => $module_data,
            form          => $input_hr,
            data          => $response,
            actionlessuri => _get_actionless_uri($safe_input_hr),
        };

        return _render_template( 'addoncgi/views/action_upgrade.tt', $data );
    }
}

sub _handle_other {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;
    my $response = Cpanel::cPAddons::Actions::handle_other( $module_data, $input_hr, $safe_input_hr, $env_hr );

    my $data = {
        environment   => $env_hr,
        module        => $module_data,
        form          => $input_hr,
        data          => $response,
        actionlessuri => _get_actionless_uri($safe_input_hr),
    };

    return _render_template( 'addoncgi/views/action_other.tt', $data );
}

sub _handle_moderation {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    my $action_response = Cpanel::cPAddons::Actions::handle_moderation( $module_data, $input_hr, $safe_input_hr, $env_hr );
    my $form_valid      = $action_response->{notices}->has( 'critical_error', 'error' ) ? 0 : 1;
    my $error_messages  = $action_response->{notices}->get_error_messages();

    require Cpanel::cPAddons::Moderation;
    my $list_response               = Cpanel::cPAddons::Moderation::list_moderation_requests();
    my $pending_moderation_requests = $list_response && !$list_response->{error} ? $list_response->{requests} : [];
    my $total_requests              = scalar @{$pending_moderation_requests};
    my $template_data               = {
        form     => $input_hr,
        safeform => $safe_input_hr,
        data     => {
            moderated_request_count                 => $total_requests,
            moderation_request_limit_reached        => Cpanel::cPAddons::Moderation::has_reached_max_moderation_req_all_mod(),
            module_moderation_request_limit_reached => Cpanel::cPAddons::Moderation::has_reached_max_moderation_req_per_mod( $module_data->{name} ),
            form_valid                              => $form_valid,
            error_messages                          => $error_messages,
        },
        environment   => $env_hr,
        module        => $module_data,
        actionlessuri => _get_actionless_uri($safe_input_hr),
    };

    return _render_template( 'addoncgi/views/moderation_request_form.tt', $template_data );
}

sub _handle_send_moderation_request {
    my ( $module_data, $input_hr, $safe_input_hr, $env_hr ) = @_;

    require Cpanel::cPAddons::Moderation;
    my $response = Cpanel::cPAddons::Moderation::create_moderation_request( $module_data->{name}, $input_hr );
    $response->{environment}   = $env_hr;
    $response->{module}        = $module_data;
    $response->{actionlessuri} = _get_actionless_uri($safe_input_hr);

    return _render_template( 'addoncgi/views/send_moderation_request.tt', $response );
}

sub _render_manager_ui {
    my ($data) = @_;

    my $action   = $data->{form}{action};
    my $response = Cpanel::cPAddons::Actions::init_module( $action, $data->{module} );
    my $actions  = {};
    if ( !$response->{error} ) {
        $actions = Cpanel::cPAddons::Actions::setup_actions( $data->{module} );
    }

    my $obj = Cpanel::cPAddons::Obj::create_obj(
        err           => $response->{error},
        env_hr        => $data->{environment},
        module_hr     => $data->{module},
        input_hr      => $data->{form},
        safe_input_hr => $data->{safeform},
        mod           => $data->{module}{name},
    );

    $data = {
        %{$data},
        data     => $obj,
        response => $response,
    };

    $data->{environment}{contactemail}                   = $obj->{contactemail} || '';
    $data->{environment}{domains}{domain_to_docroot_map} = $obj->{domain_to_docroot_map};
    $data->{environment}{domains}{list}                  = [ sort keys %{ $obj->{domain_to_docroot_map} } ];

    foreach my $instance ( @{ $data->{data}{sorted_instances} } ) {
        if ( $instance->{version} ne $data->{module}{meta}{version} ) {
            $data->{has_upgradable_instances} = 1;
            last;
        }
    }

    $data->{has_instances} = scalar @{ $data->{data}{sorted_instances} };

    if ( $data->{module}{is_deprecated} ) {

        # Deprecated modules can't install, so we'll check if there's an alternative to suggest
        my $alt_module = Cpanel::cPAddons::Module::get_alternative_for( $data->{module}{name} );
        if ( $alt_module && $alt_module->{is_installed} && !$alt_module->{is_deprecated} ) {
            $alt_module->{url}  = _to_uri( $data->{environment}, "addon=$alt_module->{name}" );
            $data->{alt_module} = $alt_module;
        }
        $data->{install_content} = _capture_template( 'addoncgi/views/install_deprecated_section.tt', $data );
    }
    elsif ( $actions->{installform} && ref $actions->{installform} eq 'CODE' ) {
        my $trap = Cpanel::FHTrap->new();
        $data->{data}{installform} = _capture_template( 'addoncgi/views/install_section.tt', $data );
        $actions->{installform}->( $data->{data}, $data->{module}{meta}, $data->{form} );
        $data->{install_content} = $trap->close;
    }
    else {
        $data->{install_content} = _capture_template( 'addoncgi/views/install_section.tt', $data );
    }

    # TODO: Make the manage section completely replaceable
    # by the addin vendor.
    # if (   $actions->{manageform} && ref $actions->{manageform} eq 'CODE') {
    #     my $trap = Cpanel::FHTrap->new();
    #     $data->{manageform} = _capture_template('addoncgi/views/manage_section.tt', $data);
    #     $actions->{manageform}->( $data->{data}, $data->{module}{meta}, $data->{form} );
    #     $data->{manage_content} = $trap->close;
    # }
    # else {
    $data->{manage_content} = _capture_template( 'addoncgi/views/manage_section.tt', $data );

    #}

    if ( $data->{module}{meta}{display}{upgrades} ) {
        if ( $actions->{upgradeform} && ref $actions->{upgradeform} eq 'CODE' ) {
            my $trap = Cpanel::FHTrap->new();
            $data->{data}{upgradeform} = _capture_template( 'addoncgi/views/upgrade_section.tt', $data );
            $actions->{upgradeform}->( $data->{data}, $data->{module}{meta}, $data->{form} );
            $data->{upgrade_content} = $trap->close;
        }
        else {
            $data->{upgrade_content} = _capture_template( 'addoncgi/views/upgrade_section.tt', $data );
        }
    }

    if ( $actions->{uninstallform} && ref $actions->{uninstallform} eq 'CODE' ) {
        my $trap = Cpanel::FHTrap->new();
        $data->{data}{uninstallform} = _capture_template( 'addoncgi/views/uninstall_section.tt', $data );
        $actions->{uninstallform}->( $data->{data}, $data->{module}{meta}, $data->{form} );
        $data->{uninstall_content} = $trap->close;
    }
    else {
        $data->{uninstall_content} = _capture_template( 'addoncgi/views/uninstall_section.tt', $data );
    }

    _render_template( 'addoncgi/views/addon_view.tt', $data );

    return;
}

sub _exit_early {
    my $exit = 0;
    my $data = {};
    if ( $ENV{'cpaddons_init_failed'} ) {
        $exit = 1;
        $data->{initialization_failed} = 1;
    }

    # Check addoncgi feature
    if ( defined $Cpanel::CPDATA{'FEATURE-ADDONCGI'}
        && $Cpanel::CPDATA{'FEATURE-ADDONCGI'} eq '0' ) {
        $exit = 1;
        $data->{feature_disabled} = 1;
    }

    if ( defined $Cpanel::CPDATA{'DEMO'} && $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $exit = 1;
        $data->{is_demo_mode} = 1;
    }

    if ( Cpanel::Server::Type::is_dnsonly() ) {
        $exit = 1;
        $data->{is_dnsonly_mode} = 1;
    }

    if ( !Cpanel::OS::supports_cpaddons() ) {
        $exit = 1;
        $data->{os_is_not_supported} = 1;
    }

    _render_template( 'addoncgi/views/exit_early.tt', $data ) if $exit;

    return $exit;
}

# TODO: Unused
sub _check_valid_module {
    my ($mod) = @_;

    my $pathx = $mod;
    $pathx =~ s/\:\:/\//g;
    $pathx =~ s/\.pm$//;

    my $notices = Cpanel::cPAddons::Notices::singleton();
    if ( $mod !~ /\A(?:(?:[A-Za-z0-9_]+::){2}[A-Za-z0-9_]+)\z/
        || !-e "/usr/local/cpanel/cpaddons/$pathx.pm" ) {

        $notices->add_critical_error( locale()->maketext('The [asis,cPAddon] that you requested contains an invalid module name.') );
        _listallmods(
            notices => $notices,
        );
        return 0;
    }
    elsif ( exists $Cpanel::cPAddons::Globals::disallowed_feat{$mod} ) {
        $notices->add_critical_error( locale()->maketext( 'The “[_1]” [asis,cPAddon] that you requested is disabled.', Cpanel::Encoder::Tiny::safe_html_encode_str($mod) ) );
        _listallmods(
            notices => $notices,
        );
        return 0;
    }

    return 1;
}

sub _get_actionless_uri {
    my ($safe_input_hr) = @_;
    my @list;
    for my $name ( keys %{$safe_input_hr} ) {
        next if grep { $name eq $_ } (qw(action license apass apass2));
        push @list, qq($name=$safe_input_hr->{$name});
    }

    my $actionlessuri = join '&', @list;
    $ENV{'actionlessuri'} = $actionlessuri;
    return $actionlessuri;
}

sub _install_template_funcs {
    my ($args) = @_;

    # Extra functions
    $args->{slugify} = \&_slugify;
    $args->{to_uri}  = \&_to_uri;
    return;
}

sub _render_template {
    my ( $path, $data ) = @_;
    my ( $ok, $output );

    my $args = { $data ? %$data : () };    # unwrap any objects

    $args->{template_file} = $path;

    _install_template_funcs($args);

    ( $ok, $output ) = Cpanel::Template::process_template( 'cpanel', $args );
    return ( $ok ? print $$output : print $output );
}

sub _capture_template {
    my ( $path, $data ) = @_;
    my ( $ok, $output );

    my $args = { $data ? %$data : () };    # unwrap any objects
    $args->{template_file} = $path;
    $args->{print}         = 0;

    _install_template_funcs($args);

    ( $ok, $output ) = Cpanel::Template::process_template( 'cpanel', $args );
    return ( $ok ? $$output : $output );
}

sub _is_module_moderated {
    my ($mod) = @_;

    my $is_moderated = 0;
    require Cpanel::cPAddons::Moderation;
    my $resp = Cpanel::cPAddons::Moderation::is_moderated($mod);
    if ( $resp->{error} ) {
        Cpanel::cPAddons::Notices::singleton()->add_error( $resp->{error} );
    }
    else {
        $is_moderated = $resp->{is_moderated} || 0;
    }
    return $is_moderated;
}

sub _is_module_approved {
    my ($mod) = @_;

    my $is_approved = 0;
    require Cpanel::cPAddons::Moderation;
    my $resp = Cpanel::cPAddons::Moderation::is_approved($mod);
    if ( $resp->{error} ) {
        Cpanel::cPAddons::Notices::singleton()->add_error( $resp->{error} );
    }
    else {
        $is_approved = $resp->{approved};
    }
    return $is_approved;
}

#### command functions ##

sub _set_user {
    my ($uid) = @_;

    my $user;
    if ( $uid == 0 ) {
        $user = $ENV{'cpasuser'};
        require Cpanel::AccessIds::SetUids;
        Cpanel::AccessIds::SetUids::setuids($user);
    }
    else {
        $user = ( Cpanel::PwCache::getpwuid($>) )[0];
    }

    Cpanel::initcp($user);

    return;
}

sub _slugify {
    my ( $text, $alt ) = @_;
    $alt = '-' if !$alt;
    $text =~ s/[^a-z0-9]+/$alt/gi;
    $text =~ s/^(?:$alt)?(.+?)(?:$alt)?$/$1/;
    $text =~ s/^(.+)$/\L$1/;
    return $text;
}

sub _to_uri {
    my $env  = shift;
    my $more = shift || '';
    my @params;
    foreach my $key (qw(verbose debug)) {
        push @params, "$key=1"
          if $env->{$key};
    }
    return $env->{script_name} . '?' . ( @params ? join( '&', @params ) : '' ) . ( $more && @params ? '&' : '' ) . ( $more ? "$more" : '' );
}

# Functions that are used by addon modules.
# These must be preserved until the indicated
# addons are updated to no longer depend on
# these private methods:
*Cpanel::cPAddons::_untaint = \&Cpanel::cPAddons::Util::_untaint;    # Used by cPanel::ECommerce::OSCommerce

1;
