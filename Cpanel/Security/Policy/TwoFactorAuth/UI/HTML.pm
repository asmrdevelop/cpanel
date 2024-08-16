package Cpanel::Security::Policy::TwoFactorAuth::UI::HTML;

# cpanel - Cpanel/Security/Policy/TwoFactorAuth/UI/HTML.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use File::Spec                 ();
use Cpanel::SecurityPolicy::UI ();
use Cpanel::Locale::Lazy 'lh';

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {
    my ( $self, $formref, $sec_ctxt ) = @_;

    my %template_vars = (
        'file'  => 'tfa_verify',
        'error' => '',
    );

    my $cpresultref = {};
    my ( $user, $homedir );
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user    = $sec_ctxt->{'possessor'};
        $homedir = $sec_ctxt->{'possessor_homedir'};
    }
    elsif ( defined $sec_ctxt->{'virtualuser'} && defined $sec_ctxt->{'domain'} ) {

        # webmail user validation
        $user = $sec_ctxt->{'virtualuser'} . '@' . $sec_ctxt->{'domain'};
    }
    else {
        $user    = $sec_ctxt->{'webmailowner'} // $sec_ctxt->{'user'};
        $homedir = $sec_ctxt->{'homedir'};
    }

    if ( !length( $sec_ctxt->{'session_id'} ) ) {
        $cpresultref->{'error'} = $template_vars{'error'} = lh()->maketext('Cookies must be enabled in your browser to log in.');
    }
    elsif ( $formref && exists $formref->{'tfatoken'} ) {
        my $valid_token = 0;
        if ($>) {
            require Cpanel::AdminBin::Call;
            $valid_token = Cpanel::AdminBin::Call::call( 'Cpanel', 'twofactorauth', 'VERIFY_TOKEN', $formref->{'tfatoken'}, $sec_ctxt );
        }
        else {
            require Cpanel::Security::Authn::TwoFactorAuth::Verify;
            $valid_token = Cpanel::Security::Authn::TwoFactorAuth::Verify::verify_token_for_user( $user, $formref->{'tfatoken'}, $sec_ctxt->{'session_id'} );
        }

        if ($valid_token) {
            if ( $sec_ctxt->{'appname'} eq 'cpaneld' ) {
                Cpanel::SecurityPolicy::UI::force_redirect("$ENV{'cp_security_token'}/frontend/$sec_ctxt->{'cptheme'}/index.html");
            }
            elsif ( $sec_ctxt->{'appname'} eq 'webmaild' ) {
                Cpanel::SecurityPolicy::UI::force_redirect("$ENV{'cp_security_token'}/webmail/jupiter/index.html");
            }
            else {
                Cpanel::SecurityPolicy::UI::force_redirect("$ENV{'cp_security_token'}/");
            }
            return $cpresultref;
        }
        else {
            $cpresultref->{'error'} = $template_vars{'error'} = lh()->maketext('The security code is invalid.');
        }
    }
    else {
        $cpresultref->{'error'} = lh()->maketext('No security code specified.');
    }

    $template_vars{'type'} = $formref->{'type'} if ref $formref;
    $template_vars{'user'} = $user;
    process_appropriate_template( \%template_vars );

    return $cpresultref;
}

sub process_appropriate_template ($opts) {

    $opts //= {};

    my $types = {
        'html' => {
            'header' => sub {

                Cpanel::SecurityPolicy::UI::html_header(
                    {
                        'small_form' => 1,
                        ( $opts->{'error'} ) ? ( 'error' => $opts->{'error'} ) : (),
                    }
                );
                return;
            },
            'footer' => sub {
                Cpanel::SecurityPolicy::UI::html_footer();
                return;
            }
        },
        'json' => {
            'header' => sub {
                Cpanel::SecurityPolicy::UI::json_header();
                return;
            }
        }
    };

    my $type = $opts->{type} || 'html';

    if ( my $header = $types->{$type}->{header} ) {
        $header->();
    }

    Cpanel::SecurityPolicy::UI::process_template( "TwoFactorAuth/$opts->{'file'}.html.tmpl", { 'user' => $opts->{'user'} } );

    if ( my $footer = $types->{$type}->{footer} ) {
        $footer->();
    }

    return;
}

# This runs as the user
sub _create_sec_policy_dir {
    my $dir = shift;

    require Cpanel::SafeDir::MK;
    Cpanel::SafeDir::MK::safemkdir( $dir, '0711' ) or die "Unable to create securitypolicy directory: $!\n";
    return;
}

1;
