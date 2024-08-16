package Whostmgr::Config;

# cpanel - Whostmgr/Config.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Template                     ();
use Cpanel::Exception                    ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Server::Type::Profile::Roles ();
use Cpanel::Template::Stash              ();
use Cpanel::LoadModule                   ();

sub apply_tweaks {    ##no critic qw(ProhibitExcessComplexity)
    my %OPTS = @_;

    my $module = $OPTS{'module'} || 'Main';
    Cpanel::Validate::FilesystemNodeName::validate_or_die($module);

    my $conf_ref = $OPTS{'conf_ref'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'conf_ref' ] ) if !$OPTS{'conf_ref'};

    my $template_coderef = $OPTS{'template_coderef'} || _default_template_coderef();
    my $redirect_stdout  = $OPTS{'redirect_stdout'};

    my %newvalues =
      ( ref $OPTS{'newvalues'} eq 'HASH' )
      ? %{ $OPTS{'newvalues'} }
      : %{$conf_ref};

    my @failed_updates;
    my @post_actions;

    Cpanel::LoadModule::load_perl_module('Whostmgr::TweakSettings');
    Whostmgr::TweakSettings::load_module($module);
    my $texts = Whostmgr::TweakSettings::get_texts($module);

    my $tweaksettings_conf_ref;
    {
        no strict 'refs';
        $tweaksettings_conf_ref = \%{"Whostmgr::TweakSettings::${module}::Conf"};
    }
    if ( !$tweaksettings_conf_ref || ref $tweaksettings_conf_ref ne 'HASH' ) {
        die("\%Whostmgr::TweakSettings::${module}::Conf could not be loaded");
    }

    $template_coderef->(
        {
            'template_file'  => 'dotweaksettings.tmpl',
            'saved'          => 1,
            'ts_conf'        => $tweaksettings_conf_ref,
            'ts_texts'       => $texts,
            'rejects'        => $OPTS{'rejects'},
            'reject_reasons' => $OPTS{'reject_reasons'},
        }
    );

    $template_coderef->(
        {
            'template_file' => 'dotweaksettings.tmpl',
            'restarted'     => 1,
        }
    );

    foreach my $key ( sort keys %{$tweaksettings_conf_ref} ) {

        #if we got nothing for this, then there is nothing to report or to do
        next if !exists $newvalues{$key};

        my $thisconf = $tweaksettings_conf_ref->{$key};

        if ( my $role_req = $thisconf->{'needs_role'} ) {
            next if !Cpanel::Server::Type::Profile::Roles::are_roles_enabled($role_req);
        }

        my $label = $texts->{$key}{'label'} || $thisconf->{'label'};

        my $is_new_setting = !exists $conf_ref->{$key};

        my $oldvalue =
            $thisconf->{'value'}
          ? $thisconf->{'value'}->($conf_ref)
          : $conf_ref->{$key};

        my $newvalue = $newvalues{$key};

        my $display_value;

        #this tests for whether both are undef
        my $changed_value = defined $oldvalue || defined $newvalue;

        my $conftype = $thisconf->{'type'} // '';

        if ( $conftype eq 'multiselect' ) {
            next if ref $newvalue ne 'HASH';

            $display_value = join( ',', sort grep { $newvalue->{$_} } keys %$newvalue );
            $OPTS{'newvalues'}{$key} = $display_value;

            my $old_concat = join( ',', sort grep { $oldvalue->{$_} } keys %$oldvalue );
            $conf_ref->{$key} = $old_concat;

            $changed_value &&= $old_concat ne $display_value;
        }
        else {
            $display_value = $newvalue;
            if ( $conftype eq 'binary' || $conftype eq 'inversebinary' ) {
                $changed_value = !!$oldvalue ne !!$newvalue;
            }
            else {
                $changed_value &&= ( defined $oldvalue && !defined $newvalue || !defined $oldvalue && defined $newvalue || $newvalues{$key} ne ( $conf_ref->{$key} // '' ) ) ? 1 : 0;
            }
        }

        if ($changed_value) {
            $template_coderef->(
                {
                    'template_file'  => 'dotweaksettings.tmpl',
                    'updating'       => 1,
                    'label'          => $label                      || $key,
                    'undef_label'    => $thisconf->{'undef'}        || $texts->{$key}{'undef'},
                    'optionlabels'   => $thisconf->{'optionlabels'} || $texts->{$key}{'optionlabels'},
                    'oldvalue'       => $conf_ref->{$key}           || '',
                    'newvalue'       => $display_value              || '',
                    'is_new_setting' => $is_new_setting,
                    'setting_data'   => $thisconf,
                }
            );
        }

        #have this always execute "action"s in case of $OPTS{'force'}
        if ( exists $thisconf->{'action'}
            && ref $thisconf->{'action'} eq 'CODE' ) {

            my $redirect_stdout_undo = $redirect_stdout && _get_stdout_redirect();

            my $isok = $thisconf->{'action'}->(
                $newvalue,
                $oldvalue,
                $OPTS{'force'},
                \%newvalues,
                $conf_ref
            );

            undef $redirect_stdout_undo;

            if ( !$isok ) {
                push @failed_updates, $key;
                $template_coderef->(
                    {
                        'template_file' => 'dotweaksettings.tmpl',
                        'is_ok'         => $isok,
                        'changed_value' => $changed_value,
                        'label'         => $label || $key,
                        'error'         => $!,                       #ignored if $isok
                        key             => $key
                    }
                );
            }
            elsif ($changed_value) {
                $template_coderef->(
                    {
                        'template_file' => 'dotweaksettings.tmpl',
                        'is_ok'         => 1,
                        'label'         => $label || $key,
                    }
                );
            }
        }
        elsif ($changed_value) {
            $template_coderef->(
                {
                    'template_file' => 'dotweaksettings.tmpl',
                    'is_ok'         => 1,
                    'label'         => $label || $key,
                }
            );
        }

        if (   ( $changed_value || $OPTS{'force'} )
            && exists $thisconf->{'post_action'}
            && ref $thisconf->{'post_action'} eq 'CODE' ) {

            push @post_actions, {
                'label'         => $label || $key,
                'changed_value' => $changed_value,
                'code'          => sub {
                    $thisconf->{'post_action'}->(
                        $newvalue,
                        $oldvalue,
                        $OPTS{'force'},
                        \%newvalues,
                        $conf_ref
                    );
                }
            };
        }
    }

    return ( 1, { 'module' => $module, 'post_actions' => \@post_actions }, \@failed_updates );
}

sub post_apply_tweaks {
    my %OPTS = @_;

    my $module           = $OPTS{'module'}           || 'Main';
    my $template_coderef = $OPTS{'template_coderef'} || _default_template_coderef();
    my $redirect_stdout  = $OPTS{'redirect_stdout'};

    foreach my $action ( @{ $OPTS{'post_actions'} } ) {
        my $label = $action->{'label'};
        my $key   = $action->{'key'};
        $template_coderef->(
            {
                'template_file' => 'dotweaksettings.tmpl',
                'post_action'   => 1,
                'label'         => $label || $key,
            }
        );

        my $redirect_stdout_undo = $redirect_stdout && _get_stdout_redirect();

        my $isok = $action->{'code'}->();

        if ( !$isok ) {
            $template_coderef->(
                {
                    'template_file' => 'dotweaksettings.tmpl',
                    'is_ok'         => $isok,
                    'changed_value' => $action->{'changed_value'},
                    'label'         => $label || $key,
                    'error'         => $!,                           #ignored if $isok
                }
            );
        }
        elsif ( $action->{'changed_value'} ) {
            $template_coderef->(
                {
                    'template_file' => 'dotweaksettings.tmpl',
                    'is_ok'         => 1,
                    'label'         => $label || $key,
                }
            );
        }

    }
    $template_coderef->(
        {
            'template_file' => 'dotweaksettings.tmpl',
            'done'          => 1,
        }
    );

    return;
}

sub _default_template_coderef {
    return sub {
        my ($input_hr) = @_;
        return Cpanel::Template::process_template(
            'whostmgr',
            $input_hr,
            { 'STASH' => Cpanel::Template::Stash->new(), },
        );

    }

}

# We need to redirect STDOUT to STDERR so any actions
# do not pollute the api output and cause
# the output from the executed commands to be sent back with the
# JSON output in an example execution such as:
# whmapi1 restore_config_from_file path=/root/cpanel.config module=Main
sub _get_stdout_redirect {
    require Cpanel::RedirectFH;
    return Cpanel::RedirectFH->new( \*STDOUT => \*STDERR );
}

1;
