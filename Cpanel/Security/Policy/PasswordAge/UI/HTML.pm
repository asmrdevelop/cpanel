package Cpanel::Security::Policy::PasswordAge::UI::HTML;

# cpanel - Cpanel/Security/Policy/PasswordAge/UI/HTML.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::ChangePasswd       ();
use Cpanel::Template           ();
use Cpanel::Email::PasswdPop   ();
use Cpanel::SecurityPolicy::UI ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::SV                 ();

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {
    my ( $self, $formref, $sec_ctxt, $cpconf ) = @_;

    my $cpresultref = {};

    my $days_since_change = int( time / ( 60 * 60 * 24 ) - $sec_ctxt->{'pass_change_time'} );
    if ( $sec_ctxt->{'appname'} eq 'cpaneld' ) {
        my $theme;
        if (
            defined $sec_ctxt->{'cptheme'}
            && (   -f "/usr/local/cpanel/base/frontend/$sec_ctxt->{'cptheme'}/passwd/index.html"
                || -f "/usr/local/cpanel/base/frontend/$sec_ctxt->{'cptheme'}/passwd/index.html.tt" )
        ) {
            $theme = $sec_ctxt->{'cptheme'};
        }
        else {

            # gets default cpanel theme (fallback code)
            require Cpanel::Conf;
            my $cp_defaults = Cpanel::Conf->new();
            $theme = $cp_defaults->cpanel_theme;
        }

        # redirect to change password file.
        Cpanel::SecurityPolicy::UI::force_redirect("$ENV{'cp_security_token'}/frontend/$theme/passwd/index.html?msg=age&days_since_change=$days_since_change");
        return $cpresultref;
    }

    my $user;
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user = $sec_ctxt->{'possessor'};
    }
    else {
        $user = $sec_ctxt->{'user'};
    }
    Cpanel::SV::untaint($user);    # TODO: brute-force

    my $policy = $self->{'policy'};

    my %template_vars = (
        'minpwstrength'     => $cpconf->{'minpwstrength'},
        'days_since_change' => $days_since_change,
        'maxage'            => $policy->conf_value( $cpconf, 'maxage' ),
        'msg'               => 'age',
        'policyuser'        => $user,
    );

    my $template;
    if ( $formref->{'formaction'} eq 'changepw' ) {
        if ( $formref->{'newpass'} ne $formref->{'newpass2'} ) {
            $cpresultref->{'changepw'} = "Passwords do not match.";
        }
        elsif ( $formref->{'oldpass'} ne $ENV{'REMOTE_PASSWORD'} ) {    #TEMP_SESSION_SAFE
            $cpresultref->{'changepw'} = "Old password incorrect.";
        }
        elsif ( $formref->{'oldpass'} eq $formref->{'newpass'} ) {
            $cpresultref->{'changepw'} = 'New password cannot be the same as old password.';
        }
        else {
            if ( !$sec_ctxt->{'is_possessed'} && $sec_ctxt->{'virtualuser'} ) {
                my ( $result, $message ) = Cpanel::Email::PasswdPop::passwd(
                    'virtualuser'  => $sec_ctxt->{'virtualuser'},
                    'new_password' => $formref->{'newpass'},
                    'homedir'      => $sec_ctxt->{'homedir'},
                    'system_user'  => $sec_ctxt->{'system_user'},
                    'domain'       => $sec_ctxt->{'domain'},
                );
                $cpresultref->{'changepw'} = $message;
                $template_vars{'result'}{'changed'} = $result;
            }
            else {
                if ( $user =~ /\@/ ) {
                    Carp::confess("User has an @ sign in the name.  This should never happen.");
                }
                my ( $result, $message, $rawout, $srvs ) = Cpanel::ChangePasswd::change_password(
                    'current_password' => $formref->{'oldpass'},
                    'new_password'     => $formref->{'newpass'},
                    'user'             => $user,
                    'ip'               => $ENV{'REMOTE_ADDR'},
                    'initiator'        => $ENV{'REMOTE_USER'},
                );
                if ($result) {
                    $cpresultref->{'changepw'} = '<pre>' . Cpanel::Encoder::Tiny::safe_html_encode_str($rawout) . '</pre>';
                }
                else {
                    $cpresultref->{'changepw'} = $message;
                }
                $template_vars{'result'}{'changed'} = $result;
            }

        }
        $template_vars{'result'}{'changepw'} = $cpresultref->{'changepw'};
        $template = 'changed';
    }
    else {
        $template = 'main';
    }

    process_appropriate_template(
        'app'  => $sec_ctxt->{'appname'},
        'file' => $template,
        'data' => \%template_vars,
    );
    return $cpresultref;
}

sub process_appropriate_template {
    my (%opts) = @_;

    if ( $opts{'app'} eq 'whostmgrd' ) {
        Cpanel::SecurityPolicy::UI::html_http_header();
        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => "security/Password/$opts{'file'}.tmpl",
                'data'          => $opts{'data'},
            }
        );
    }
    else {
        Cpanel::SecurityPolicy::UI::html_header();
        Cpanel::SecurityPolicy::UI::process_template( "PasswdAge/$opts{'file'}.html.tmpl", $opts{'data'} );
        Cpanel::SecurityPolicy::UI::html_footer();
    }
}

1;
