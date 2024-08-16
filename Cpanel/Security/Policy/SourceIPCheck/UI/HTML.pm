package Cpanel::Security::Policy::SourceIPCheck::UI::HTML;

# cpanel - Cpanel/Security/Policy/SourceIPCheck/UI/HTML.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# The following dependencies must be included by cpsrvd.pl to be available in binary
use Cpanel::Encoder::Tiny                         ();
use Cpanel::SecurityPolicy::Utils                 ();
use Cpanel::Security::Policy::SourceIPCheck::Util ();
use Cpanel::Config::Hulk                          ();
use Cpanel::Hulk                                  ();
use Cpanel::App                                   ();
use Cpanel::LoginTheme                            ();
use Cpanel::SecurityPolicy::UI                    ();
use Cpanel::SV                                    ();

use Cpanel::Locale::Lazy 'lh';

sub MATCH_FRACTION { 0.75; }

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub process {    ##no critic qw(ExcessComplexity) - needs scrum
    my ( $self, $formref, $sec_ctxt ) = @_;

    my $homedir;
    my $user;
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user    = $sec_ctxt->{'possessor'};
        $homedir = $sec_ctxt->{'possessor_homedir'};
    }
    else {
        $user    = $sec_ctxt->{'user'};
        $homedir = $sec_ctxt->{'homedir'};
    }

    Cpanel::SV::untaint($_) foreach ( $user, $homedir );

    my $sec_policy_dir = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($homedir);

    die "Invalid user: “$user”" if -1 != index( $user, '/' );

    my $service = 'secpol';
    $service = 'mail-secpol' if $Cpanel::App::appname eq 'webmaild' && $user =~ /[\+\%\@]/;

    my $cpresultref = {};

    # Need to check here and disallow if brute force has been triggered.
    my $cphulk = Cpanel::Hulk->new();
    if ( Cpanel::Config::Hulk::is_enabled() && $cphulk->connect() && $cphulk->register($Cpanel::App::appname) ) {
        my $ok_to_login = $cphulk->pre_login(
            user          => $user,
            'remote_ip'   => $ENV{'REMOTE_ADDR'} || '',
            'local_ip'    => $ENV{'SERVER_ADDR'} || '',
            'remote_port' => $ENV{'REMOTE_PORT'} || '',
            'local_port'  => $ENV{'SERVER_PORT'} || '',
            status        => 1,
            service       => $service,
            auth_service  => $Cpanel::App::appname
        );
        if ( $ok_to_login == &Cpanel::Hulk::HULK_ERROR || $ok_to_login == &Cpanel::Hulk::HULK_FAILED ) {
            print STDERR "Brute force checking was skipped because cphulkd failed to process “$user” from “$ENV{'REMOTE_ADDR'}” for the “$service (secques)” service.\n";
            $cphulk->deregister();
            undef $cphulk;    # Do not try can_login below because this failed.
        }
        elsif ( $ok_to_login != &Cpanel::Hulk::HULK_OK ) {
            $cpresultref->{'answerquestions'} = lh()->maketext( 'Brute force attempt on security questions has locked out account “[_1]”.', $user );
            my %template_vars = (
                'policyuser' => $user,
                'result'     => {
                    'user'            => $user,
                    'questions'       => $cpresultref->{'questions'},             # if they are from us they are already localized, if they are from them they do not need localized
                    'answerquestions' => $cpresultref->{'answerquestions'},
                    'login_theme'     => Cpanel::LoginTheme::get_login_theme(),
                }
            );
            process_appropriate_template(
                'app'  => $sec_ctxt->{'appname'},
                'file' => 'respond',
                'data' => \%template_vars,
            );
            return;
        }
    }
    else {
        undef $cphulk;
    }

    # actual processing code
    my $has_security_questions = Cpanel::Security::Policy::SourceIPCheck::Util::has_security_questions( $sec_policy_dir, $user );
    my $qvalid;
    if ( $formref->{'formaction'} =~ /(set|verify)questions/ ) {
        $qvalid = Cpanel::Security::Policy::SourceIPCheck::Util::validatesecquestions( $formref, $cpresultref );
    }

    my %template_vars = (
        'login_theme' => Cpanel::LoginTheme::get_login_theme(),
        'policyuser'  => $user,
    );
    my $template;
    my $questions = {};
    if ( $formref->{'formaction'} eq 'verifyquestions' && $qvalid ) {
        $template = 'set';
    }
    elsif ( $formref->{'formaction'} eq 'setquestions' && !$has_security_questions && $qvalid ) {
        Cpanel::Security::Policy::SourceIPCheck::Util::authorize_my_ip( $sec_policy_dir, $user, $sec_ctxt->{'remoteip'} );
        Cpanel::Security::Policy::SourceIPCheck::Util::savesecquestions( $sec_policy_dir, $formref, $user );
        $template = 'set-done';
        $template_vars{'action'} = 'set-done';
    }
    elsif ( !$has_security_questions ) {
        $template = 'main';
        $template_vars{'action'} = 'setquestions';
    }
    elsif ( $formref->{'formaction'} eq 'respondquestions' ) {
        my $is_successful = 0;
        eval {
            Cpanel::Security::Policy::SourceIPCheck::Util::loadsecquestions( $sec_policy_dir, $questions, $user );

            # TODO : After 11.36, we might want to remove this once we're sure none of the old files are lying about.
            my $old_style  = Cpanel::Security::Policy::SourceIPCheck::Util::old_style_secquestion( $sec_policy_dir, $user );
            my $matchcount = 0;
            for ( 1 .. Cpanel::Security::Policy::SourceIPCheck::Util::NUM_QUESTIONS ) {
                my $answer = $formref->{ 'answer' . $_ };

                # TODO : After 11.36, we might want to remove this once we're sure none of the old files are lying about
                if ($old_style) {
                    $answer = lc $answer;
                    $answer =~ s/\s+//;
                }
                if ( $questions->{ 'seca' . $_ } eq Cpanel::Security::Policy::SourceIPCheck::Util::digest_answer( $answer, $user ) ) {
                    $matchcount++;
                }
            }

            # You have to get at least the specified fraction of questions correct.
            if ( MATCH_FRACTION() <= $matchcount / Cpanel::Security::Policy::SourceIPCheck::Util::NUM_QUESTIONS ) {
                Cpanel::Security::Policy::SourceIPCheck::Util::authorize_my_ip( $sec_policy_dir, $user, $sec_ctxt->{'remoteip'} );
                $cpresultref->{'answerquestions'} = 'You have answered your security questions correctly.';
                $is_successful = 1;
            }
            else {
                $cpresultref->{'answerquestions'} = 'Sorry, your answers did not match.';
            }
            1;
        } or do {

            # Use the supplied exception message or a generic message if none.
            $cpresultref->{'answerquestions'} = $@ || 'Unable to check security questions.';
        };

        if ( $cphulk && Cpanel::Config::Hulk::is_enabled() ) {
            my $ok_to_login = $cphulk->can_login(
                user          => $user,
                'ip'          => $ENV{'REMOTE_ADDR'} || '',
                'local_ip'    => $ENV{'SERVER_ADDR'} || '',
                'remote_port' => $ENV{'REMOTE_PORT'} || '',
                'local_port'  => $ENV{'SERVER_PORT'} || '',
                status        => $is_successful,
                service       => $service,
                auth_service  => $Cpanel::App::appname,
                deregister    => 1,                       # disconnect hulk
            );
            if ( $ok_to_login == &Cpanel::Hulk::HULK_ERROR || $ok_to_login == &Cpanel::Hulk::HULK_FAILED ) {
                print STDERR "Brute force checking was skipped because cphulkd failed to process “$user” from “$ENV{'REMOTE_ADDR'}” for the “$service (secques)” service.\n";
            }
            elsif ( $ok_to_login == &Cpanel::Hulk::HULK_HIT ) {
                $cpresultref->{'answerquestions'} = lh()->maketext( 'The system has registered a brute force attempt on security questions for the account “[_1]”.', $user );
            }
            elsif ( $ok_to_login != &Cpanel::Hulk::HULK_OK ) {
                $cpresultref->{'answerquestions'} = lh()->maketext( 'Brute force attempt on security questions has locked out account “[_1]”.', $user );
            }
        }

        $template = 'respond';
        $template_vars{'action'} = 'challenge-done';
    }
    else {
        Cpanel::Security::Policy::SourceIPCheck::Util::loadsecquestions( $sec_policy_dir, $questions, $user );
        $template = 'answer';
        $template_vars{'action'} = 'challenge';
    }

    # Set up template parameters.
    $template_vars{'result'} = {
        'questions'       => $cpresultref->{'questions'},         # if they are from us they are already localized, if they are from them they do not need localized
        'answerquestions' => $cpresultref->{'answerquestions'},
    };
    $template_vars{'securityquestion'}->[0] = lh()->maketext('Please select a question:');
    push @{ $template_vars{'securityquestion'} }, Cpanel::Security::Policy::SourceIPCheck::Util::samplequestions();    # why not just have the template do the talking?

    foreach my $n ( 1 .. 4 ) {
        if ( exists $formref->{"q${n}ques"} or exists $questions->{"secq$n"} ) {
            my $ques = $formref->{"q${n}ques"} ? Cpanel::Encoder::Tiny::safe_html_encode_str( $formref->{"q${n}ques"} ) : $questions->{"secq$n"};
            $template_vars{'userquestion'}->{$n} = $ques;
        }
        my $key = "q${n}answer";
        if ( exists $formref->{$key} ) {
            $template_vars{$key} = Cpanel::Encoder::Tiny::safe_html_encode_str( $formref->{$key} );
        }
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

    Cpanel::SecurityPolicy::UI::html_header( $opts{'data'} );
    Cpanel::SecurityPolicy::UI::process_template( "SourceIPCheck/$opts{'file'}.html.tmpl", $opts{'data'} );
    Cpanel::SecurityPolicy::UI::html_footer( $opts{'data'} );
}

1;
