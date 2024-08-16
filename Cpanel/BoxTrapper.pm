package Cpanel::BoxTrapper;

# cpanel - Cpanel/BoxTrapper.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Imports;

use Cpanel::Autodie                         ();
use Time::Local                             ();
use Cpanel::Exception                       ();
use Cpanel::SafeFile                        ();
use Cpanel::SafeFile::Replace               ();
use Cpanel::Encoder::Tiny                   ();
use Cpanel::Encoder::URI                    ();
use Cpanel::Exception                       ();
use Cpanel                                  ();
use Cpanel::Locale                          ();
use Cpanel::StringFunc::SplitBreak          ();
use Cpanel::Regex                           ();
use Cpanel::Logger                          ();
use Cpanel::BoxTrapper::CORE                ();
use Cpanel::Validate::EmailCpanel           ();
use Cpanel::Validate::EmailLocalPart        ();
use Cpanel::Validate::Time                  ();
use Cpanel::Validate::Boolean               ();
use Cpanel::CPAN::Encode::MIME::Header      ();
use Cpanel::HTTP::QueryString               ();
use Cpanel::SafeDir::MK                     ();
use Cpanel::SafeRun::Simple                 ();
use Cpanel::Server::Type::Role::MailReceive ();

use HTML::Entities ();

use constant _ENOENT               => 2;
use constant DEFAULT_TEMPLATE_PATH => '/usr/local/cpanel/etc/boxtrapper/forms';
use constant DEFAULT_TEMPLATES     => qw(blacklist returnverify verifyreleased verify);
use constant MAX_TEMPLATE_SIZE     => 4096;

our $VERSION = '2.2';

# These are arbitrary, but since most spam scores are
# in the range of 2.5 to 10, this should be enough range.
our $MAX_SPAM_SCORE = 10000;
our $MIN_SPAM_SCORE = -10000;

my $logger = Cpanel::Logger->new();

sub BoxTrapper_init { }
*BoxTrapper_initvars                           = *Cpanel::BoxTrapper::CORE::BoxTrapper_initvars;
*BoxTrapper_addaddytolist                      = *Cpanel::BoxTrapper::CORE::BoxTrapper_addaddytolist;
*BoxTrapper_checkdeadq                         = *Cpanel::BoxTrapper::CORE::BoxTrapper_checkdeadq;
*BoxTrapper_checklist                          = *Cpanel::BoxTrapper::CORE::BoxTrapper_checklist;
*BoxTrapper_cleanlist                          = *Cpanel::BoxTrapper::CORE::BoxTrapper_cleanlist;
*BoxTrapper_clog                               = *Cpanel::BoxTrapper::CORE::BoxTrapper_clog;
*BoxTrapper_delivermessage                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_delivermessage;
*BoxTrapper_extractaddress                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_extractaddress;
*BoxTrapper_extractaddresses                   = *Cpanel::BoxTrapper::CORE::BoxTrapper_extractaddresses;
*BoxTrapper_extractall                         = *Cpanel::BoxTrapper::CORE::BoxTrapper_extractall;
*BoxTrapper_extract_headers_return_bodyglobref = *Cpanel::BoxTrapper::CORE::BoxTrapper_extract_headers_return_bodyglobref;
*BoxTrapper_extractbody                        = *Cpanel::BoxTrapper::CORE::BoxTrapper_extractbody;
*BoxTrapper_findreturnaddy                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_findreturnaddy;
*BoxTrapper_getaccountinfo                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_getaccountinfo;
*BoxTrapper_getdomainowner                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_getdomainowner;
*BoxTrapper_getemaildirs                       = *Cpanel::BoxTrapper::CORE::BoxTrapper_getemaildirs;
*BoxTrapper_getheader                          = *Cpanel::BoxTrapper::CORE::BoxTrapper_getheader;
*BoxTrapper_getheaders                         = *Cpanel::BoxTrapper::CORE::BoxTrapper_getheaders;
*BoxTrapper_getheadersfromfile                 = *Cpanel::BoxTrapper::CORE::BoxTrapper_getheadersfromfile;
*BoxTrapper_gethomedir                         = *Cpanel::BoxTrapper::CORE::BoxTrapper_gethomedir;
*BoxTrapper_getmailuser                        = *Cpanel::BoxTrapper::CORE::BoxTrapper_getmailuser;
*BoxTrapper_getourid                           = *Cpanel::BoxTrapper::CORE::BoxTrapper_getourid;
*BoxTrapper_getqueueid                         = *Cpanel::BoxTrapper::CORE::BoxTrapper_getqueueid;
*BoxTrapper_getranddata                        = *Cpanel::BoxTrapper::CORE::BoxTrapper_getranddata;
*BoxTrapper_getsender                          = *Cpanel::BoxTrapper::CORE::BoxTrapper_getsender;
*BoxTrapper_getrecievedfrom                    = *Cpanel::BoxTrapper::CORE::BoxTrapper_getrecievedfrom;
*BoxTrapper_gettransportmethod                 = *Cpanel::BoxTrapper::CORE::BoxTrapper_gettransportmethod;
*BoxTrapper_getwebdomain                       = *Cpanel::BoxTrapper::CORE::BoxTrapper_getwebdomain;
*BoxTrapper_isfromself                         = *Cpanel::BoxTrapper::CORE::BoxTrapper_isfromself;
*BoxTrapper_loadconf                           = *Cpanel::BoxTrapper::CORE::BoxTrapper_loadconf;
*BoxTrapper_loadfwdlist                        = *Cpanel::BoxTrapper::CORE::BoxTrapper_loadfwdlist;
*BoxTrapper_logmatch                           = *Cpanel::BoxTrapper::CORE::BoxTrapper_logmatch;
*BoxTrapper_loopprotect                        = *Cpanel::BoxTrapper::CORE::BoxTrapper_loopprotect;
*BoxTrapper_nicedate                           = *Cpanel::BoxTrapper::CORE::BoxTrapper_nicedate;
*BoxTrapper_removefromsearchdb                 = *Cpanel::BoxTrapper::CORE::BoxTrapper_removefromsearchdb;
*BoxTrapper_updatesearchdb                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_updatesearchdb;
*BoxTrapper_rebuildsearchdb                    = *Cpanel::BoxTrapper::CORE::BoxTrapper_rebuildsearchdb;
*BoxTrapper_queuemessage                       = *Cpanel::BoxTrapper::CORE::BoxTrapper_queuemessage;
*BoxTrapper_sendformmessage                    = *Cpanel::BoxTrapper::CORE::BoxTrapper_sendformmessage;
*BoxTrapper_splitaddresses                     = *Cpanel::BoxTrapper::CORE::BoxTrapper_splitaddresses;
*_writesearchdb                                = *Cpanel::BoxTrapper::CORE::_writesearchdb;

sub _role_is_enabled {
    if ( !eval { Cpanel::Server::Type::Role::MailReceive->verify_enabled(); 1 } ) {
        $Cpanel::CPERROR{'boxtrapper'} = $@->to_locale_string_no_id();
        return undef;
    }

    return 1;
}

=head1 MODULE

C<Cpanel::BoxTrapper>

=head1 DESCRIPTION

C<Cpanel::BoxTrapper> provides the implementation for BoxTrapper
along with C<Cpanel::BoxTrapper::CORE> which has most of its methods
imported here.

Many of these methods are also exposed as API 1 methods.

UAPI methods in C<Cpanel::API::BoxTrapper> make use of this same
code base but alter the error handling semantics to throw errors
and may also alter other aspects of the code to not print to STDOUT
or have other side-effects.

=head1 CONSTANTS

=head2 $MAX_EMAIL_LINES_TO_PRINT

The maximum number of line of a blocked email to print or return from
the relevant API calls.

=cut

our $MAX_EMAIL_LINES_TO_PRINT = 200;

=head1 FUNCTIONS

=cut

sub BoxTrapper_listpops {
    return if !_role_is_enabled();

    if ( exists $INC{'Cpanel/Email.pm'} ) {
        return wantarray ? Cpanel::Email::listpops() : [ Cpanel::Email::listpops() ];
    }
    else {
        my $handoff = ( -x $Cpanel::root . '/cpanel-email.pl' ? $Cpanel::root . '/cpanel-email.pl' : $Cpanel::root . '/cpanel-email' );
        my @ARR =
          split( /\n/, Cpanel::SafeRun::Simple::saferun( $handoff, 'listpops' ) );
        return wantarray ? @ARR : \@ARR;
    }

    return;
}

sub BoxTrapper_accountmanagelist {
    my $link = shift;

    return if !Cpanel::Server::Type::Role::MailReceive->is_enabled();

    my $locale = Cpanel::Locale->get_handle();

    my $POPS = BoxTrapper_listpops();

    unshift @{$POPS}, $Cpanel::user;
    my $bg = 'even';
    foreach my $pop ( sort @{$POPS} ) {
        next if ( $Cpanel::appname eq 'webmail' && $pop ne $Cpanel::authuser );

        my $enabled = BoxTrapper_isenabled($pop);
        my $status;
        if ($enabled) {
            $status = qq{<font class="redtext">} . $locale->maketext('Enabled') . '</font>';
        }
        else {
            $status = qq{<font class="blacktext">} . $locale->maketext('Disabled') . '</font>';
        }
        my $manage = $locale->maketext('Manage');
        print <<"EOM";
<tr class="info-$bg">
    <td>$pop</td>
    <td>$status</td>
    <td><a href="$link?account=$pop">$manage</a></td>
</tr>
EOM
        $bg eq 'even' ? $bg = 'odd' : $bg = 'even';
    }

    return;
}

sub api2_accountmanagelist {
    my %OPTS = @_;
    my $POPS = BoxTrapper_listpops();
    my $regex;
    if ( $OPTS{'regex'} ) {
        eval {
            local $SIG{'__DIE__'} = sub { 1 };
            $regex = qr/$OPTS{'regex'}/i;
        };
        if ( !$regex ) {
            $Cpanel::CPERROR{'boxtrapper'} = 'Invalid regex';
            return;
        }
    }
    unshift @{$POPS}, $Cpanel::user;
    my $count  = 0;
    my $locale = Cpanel::Locale->get_handle();

    my $enabled_txt  = $locale->maketext('Enabled');
    my $disabled_txt = $locale->maketext('Disabled');
    my $enabled;
    return map {
        {
            'account'    => $_,
            'accounturi' => Cpanel::Encoder::URI::uri_encode_str($_),
            'status'     => ( ( $enabled = BoxTrapper_isenabled($_) ) ? $enabled_txt : $disabled_txt ),
            'enabled'    => $enabled, 'bg' => ( $count++ % 2 == 0 ? 'even' : 'odd' ),
        }
      }
      grep { !( ( $Cpanel::appname eq 'webmail' && $_ ne $Cpanel::authuser ) || ( defined $regex && $_ !~ $regex ) ) }
      sort @{$POPS};
}

# Provides both API1 and UAPI error behavior depending on the presence of the $opts flags.
# When $opts is not defined, it falls back to api1 behavior. You can pass either a string
# or a Cpanel::Exception.
sub _handle_error {
    my ( $error, $opts ) = @_;

    my $output;
    if ( UNIVERSAL::isa( $error, 'Cpanel::Exception' ) ) {
        $output = $error->to_string();
    }
    else {
        $output = $error;
    }

    if ( $opts->{api1} ) {
        $Cpanel::CPERROR{'boxtrapper'} = $output;
        print Cpanel::Encoder::Tiny::safe_html_encode_str($output) . "\n";
    }
    elsif ( $opts->{uapi} ) {
        die Cpanel::Exception->create_raw($output);
    }
    return;
}

# Provides both API1 and UAPI warn behavior depending on the presence of the $opts flags.
sub _handle_warn {
    my ( $error, $log, $opts ) = @_;

    my $output;
    if ( UNIVERSAL::isa( $error, 'Cpanel::Exception' ) ) {
        $output = $error->to_string();
    }
    else {
        $output = $error;
    }

    logger()->warn($log);
    if ( $opts->{api1} ) {
        $Cpanel::CPERROR{'boxtrapper'} = $output;
        print Cpanel::Encoder::Tiny::safe_html_encode_str($output) . "\n";
    }
    elsif ( $opts->{uapi} ) {
        die Cpanel::Exception->create_raw($output);    # for UAPI we will always throw too
    }

    return;
}

=head2 BoxTrapper_changestatus(ACCOUNT, ACTION, OPTS)

Enable or disable BoxTrapper for an ACCOUNT.

=head3 NOTES

This is the API 1 implemenation and is used internally
by the UAPI call Cpanel::API::BoxTrapper::set_status

=head3 ARGUMENTS

=over

=item ACCOUNT - string

Either a cpanel user name or an email account.

=item ACTION - string

When equal to 'enable' will enable BoxTrapper for the account. Otherwise, it will disable BoxTrapper for the account.

=item OPTS - hashref

=over

=item api1 - Boolean

Provides error handing and output using API 1 semantics. (print, Cpanel::CPERROR)

=item uapi - Boolean

Provide error handling by throwing exceptions

=item validate - Boolean

Enabled ownership and existence validation for the email account. Defaults to not performing the validation.

=back

=back

=head3 RETURNS

1 when it succeeds.

When in 'api1' mode, it will return undef on any error.

When in 'uapi' mode, all error are thrown as exceptions.

=head3 SIDE EFFECTS

Note that in 'api1' mode there are several possible side effects:

=over

=item There may be prints to STDOUT

=item There may be values set to $Cpanel::CPERROR{'boxtrapper'}

=back

=cut

sub BoxTrapper_changestatus {
    my ( $account, $action, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    _assert_feature_enabled();

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    if ( !$account ) {
        Cpanel::Logger::cplog( 'Missing argument', 'warn', __PACKAGE__, 1 );
        _handle_error(
            locale()->maketext('Failed to change the status of [asis,BoxTrapper].'),
            $opts,
        );
        return;
    }

    my ($homedir) = BoxTrapper_getaccountinfo( $account, undef, $opts );
    if ( !$homedir ) {
        _handle_error(
            locale()->maketext( '[asis,BoxTrapper] failed to locate a home directory for “[_1]”.', $account ),
            $opts,
        );
        return;
    }

    #Suppress the filesystem changes here because all we need is $emaildir,
    #which can be gotten more simply. That way, if there’s a problem like
    #being over quota, we can give the caller an accurate failure message.
    my ($emaildir) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        $Cpanel::BoxTrapper::CORE::SKIP_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::CREATE_EMAIL_DIRS,
        $opts
    );
    if ( !$emaildir ) {
        _handle_error(
            locale()->maketext( '[asis,BoxTrapper] failed to locate a mail directory for “[_1]”.', $account ),
            $opts,
        );
        return;
    }

    my $flag_file = "$emaildir/.boxtrapperenable";

    if ( $action =~ m/enable/i ) {

        my $filelock = Cpanel::SafeFile::safeopen( my $BX, '>>', $flag_file );
        if ( !$filelock ) {
            my $error = $!;
            _handle_warn(
                locale()->maketext( "The system failed to enable [asis,BoxTrapper] because it couldn’t create “[_1]” due to an error: [_2]", $flag_file, $error ),
                "The system failed to enable BoxTrapper because it couldn’t create “$flag_file” due to an error: $error",
                $opts,
            );
            return;
        }
        Cpanel::SafeFile::safeclose( $BX, $filelock );

        if ( $opts->{api1} ) {
            print locale()->maketext('Enabled');
        }

        return 1;
    }
    else {
        unlink $flag_file or do {
            if ( !$!{'ENOENT'} ) {
                _handle_error(
                    locale()->maketext( 'The system failed to disable [asis,BoxTrapper] because it couldn’t delete “[_1]” due to an error: [_2]', $flag_file, $! ),
                    $opts,
                );
                return;
            }
        };

        if ( $opts->{api1} ) {
            print locale()->maketext('Disabled');
        }
        return 1;
    }
}

sub BoxTrapper_editmsg {
    my ( $account, $message ) = @_;

    return if !_role_is_enabled();

    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $error = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        $Cpanel::CPERROR{'boxtrapper'} = $error;
        print $error;
        return;
    }

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', Cpanel::Encoder::Tiny::safe_html_encode_str($account) ) . "\n";
        return;
    }

    $message =~ s/$Cpanel::Regex::regex{'forwardslash'}//g;
    $message =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    if ( !-e $emaildir . '/.boxtrapper/forms/' . $message ) {
        system 'cp', '-f', '/usr/local/cpanel/etc/boxtrapper/forms/' . $message, $emaildir . '/.boxtrapper/forms/' . $message;
    }

    return;
}

sub BoxTrapper_listmsgs {
    my ( $account, $editfile, $resetfile ) = @_;

    return if !_role_is_enabled();

    my $locale = Cpanel::Locale->get_handle();
    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    if ( !$account ) {
        Cpanel::Logger::cplog( 'Missing arguments', 'warn', __PACKAGE__, 1 );
        return;
    }
    if ( !$editfile ) {
        $editfile = 'editmsg.html';
    }
    if ( !$resetfile ) {
        $resetfile = 'resetmsg.html';
    }

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', Cpanel::Encoder::Tiny::safe_html_encode_str($account) ) . "\n";
        return;
    }
    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    return if !$emaildir;

    my $html_safe_account  = Cpanel::Encoder::Tiny::safe_html_encode_str($account);
    my $html_safe_emaildir = Cpanel::Encoder::Tiny::safe_html_encode_str($emaildir);
    if ( opendir my $fm_dh, '/usr/local/cpanel/etc/boxtrapper/forms' ) {
        while ( my $form = readdir $fm_dh ) {
            next if ( $form =~ m/^\./ || $form !~ m/(.+)\.txt$/ );
            $form = $1;
            my $edit           = $locale->maketext('Edit');
            my $reset          = $locale->maketext('Reset to Default');
            my $html_safe_form = Cpanel::Encoder::Tiny::safe_html_encode_str($form);
            print <<"EOM";
<tr>
    <td>$html_safe_form</td>
    <td>
        <form action="$editfile" method="post">
            <input type="hidden" name="account" value="$html_safe_account">
            <input type="hidden" name="form" value="${html_safe_form}.txt">
            <input type="hidden" name="emaildir" value="$html_safe_emaildir/.boxtrapper/forms">
            <input type="submit" class="input-button" value="$edit">
        </form>
    </td>
    <td>
        <form action="$resetfile" method="post">
            <input type="hidden" name="account" value="$html_safe_account">
            <input type="hidden" name="form" value="${html_safe_form}.txt">
            <input type="hidden" name="emaildir" value="$html_safe_emaildir/.boxtrapper/forms">
            <input type="submit" class="input-button" value="$reset">
        </form>
    </td>
</tr>
EOM
        }
        closedir $fm_dh;
    }
    else {
        Cpanel::Logger::cplog( "Unable to open BoxTrapper forms directory: $!", 'warn', __PACKAGE__, 1 );
    }

    return;
}

sub BoxTrapper_logcontrols {

    my ( $logdate, $account, $bxaction ) = @_;
    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    if ( !$account ) {
        Cpanel::Logger::cplog( 'Missing arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    return if !_role_is_enabled();

    $logdate  ||= "";
    $bxaction ||= "";

    if ( $logdate eq '' ) {
        $logdate = time();
    }
    elsif ( $logdate =~ tr/0-9//c ) {

        # This method generates HTML controls for moving back and forward through the log dates in the BoxTrapper UI.
        # Instead of displaying an error if the log date is invalid, just don't generate any controls.
        # The showlog method will print an error in an appropriate location in the UI.
        return;
    }

    print '<td align="left">';
    my $nd = ( $logdate - 86400 );
    my ( $mon, $mday, $year ) = BoxTrapper_nicedate($nd);

    print "<form action=\"$ENV{'SCRIPT_URI'}\" method=\"post\">";
    print "<input type=\"hidden\" name=\"bxaction\" value=\"${bxaction}\">";
    print "<input type=\"hidden\" name=\"account\" value=\"${account}\">";
    print "<input type=\"hidden\" name=\"logdate\" value=\"${nd}\">";
    print "<button class=\"btn btn-link\">&lt;&lt; ${mon}-${mday}-${year}</button>";
    print "</form>";

    print "</td><td align=\"center\">\n";
    ( $mon, $mday, $year ) = BoxTrapper_nicedate($logdate);
    print "${mon}-${mday}-${year}";
    print "</td><td align=\"right\">\n";
    $nd = ( $logdate + 86400 );
    ( $mon, $mday, $year ) = BoxTrapper_nicedate($nd);

    print "<form action=\"$ENV{'SCRIPT_URI'}\" method=\"post\">";
    print "<input type=\"hidden\" name=\"bxaction\" value=\"${bxaction}\">";
    print "<input type=\"hidden\" name=\"account\" value=\"${account}\">";
    print "<input type=\"hidden\" name=\"logdate\" value=\"${nd}\">";
    print "<button class=\"btn btn-link\">${mon}-${mday}-${year} &gt;&gt;</button>";
    print "</form>";

    print "</td>\n";

    return;
}

=head2 _try_action(SUB, DEFAULT) [PRIVATE]

Helper to trap and report an exception as an error property on a call.

=head3 ARGUMENTS

=over

=item SUB - code

Code to call. If it throws an exception the exception is added to the default passed in the error property.

=item DEFAULT - hashref

With the default structure for a failure for the action.

=back

=head3 RETURNS

A hash with details about the action processed.

=cut

sub _try_action {
    my ( $sub, $default ) = @_;
    my $response = eval { $sub->() };
    if ( my $exception = $@ ) {
        $response = {
            %$default,
            failed => 1,
            reason => Cpanel::Exception::get_string($exception) || '',
        };
    }
    else {
        $response = {
            %$default,
            %$response,
        };
    }
    return $response;
}

=head2 process_message_action(EMAIL, FILES, ACTIONS, OPTS)

Process the list of actions on each file in the files list. All these must
exist in the BoxTrapper queue for the requested email account.

=head3 ARGUEMNTS

=over

=item EMAIL - string

Email address who owns the blocked messages.

=item FILES - string[]

List of queuefiles to process from the BoxTrapper queue directory for the requested email address.

=item ACTIONS - string[]

List of actions to perform with the requested queued messages.

=item OPTS - hash

Controls how output is handled.

=back

Returns a list of hashes where each hash is the results of attempting a given operation on a given queued message file.

For details on the hash formats see each of the following for the actions requested:

=over

=item * L<deliver|Cpanel/API/BoxTrapper/"deliver_messages()">

=item * L<deliverall|Cpanel/API/BoxTrapper/"deliver_messages()">

=item * L<delete|Cpanel/API/BoxTrapper/"delete_messages()">

=item * L<deleteall|Cpanel/API/BoxTrapper/"delete_messages()">

=item * L<blacklist|Cpanel/API/BoxTrapper/"blacklist_messages()">

=item * L<whitelist|Cpanel/API/BoxTrapper/"whitelist_messages()">

=item * L<ignore|Cpanel/API/BoxTrapper/"ignore_messages()">

=back

=cut

sub process_message_action {
    my ( $account, $files, $actions, $opts ) = @_;
    $opts = { uapi => 1, validate => 1 } if !$opts;

    return if !_role_is_enabled();

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        _handle_error( locale()->maketext('Sorry, this feature is disabled in demo mode.'), $opts );
        return;
    }

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    require Cpanel::BoxTrapper::Actions;

    my @log;
  FILE: for my $file (@$files) {
        my ($id) = ( $file =~ m/(.*)\.msg$/ );

        my $ACTIONS = eval {
            Cpanel::BoxTrapper::Actions->new(
                {
                    account      => $account,
                    message_file => $file,
                },
                $opts,
            );
        };
        if ( my $exception = $@ ) {
            push @log, {
                matches => [$id],
                email   => $ACTIONS->{email},
                failed  => 1,
                reason  => $exception,
            };
            next FILE;
        }

        foreach my $action (@$actions) {
            if ( $action eq 'deliverall'
                && !$ACTIONS->is_operator_available('deliverall') ) {
                $action = 'deliver';
            }

            my $default = {
                email    => $ACTIONS->{email},
                matches  => [$id],
                operator => $action,
            };

            my $response;
            if ( $action eq 'whitelist' ) {
                $response = _try_action( sub { $ACTIONS->whitelist() }, $default );
            }
            elsif ( $action eq 'blacklist' ) {
                $response = _try_action( sub { $ACTIONS->blacklist() }, $default );
            }
            elsif ( $action eq 'ignore' ) {
                $response = _try_action( sub { $ACTIONS->ignore() }, $default );
            }
            elsif ( $action eq 'deliverall' ) {
                $response = _try_action( sub { $ACTIONS->deliver_all() }, $default );
            }
            elsif ( $action eq 'deliver' ) {
                $response = _try_action( sub { $ACTIONS->deliver() }, $default );
            }
            elsif ( $action eq 'delete' ) {
                $response = _try_action( sub { $ACTIONS->delete() }, $default );
            }
            elsif ( $action eq 'deleteall' ) {
                $response = _try_action( sub { $ACTIONS->delete_all() }, $default );
            }
            else {
                $response = {
                    email   => $ACTIONS->{email},
                    matches => [$id],
                    failed  => 1,
                    reason  => locale()->maketext( 'The system does not support the requested action: [_1]', $action ),
                };
            }

            push @log, $response;
            next FILE if $response->{failed};
        }
    }
    return \@log;
}

# DEPRECATED: Remove once API 1 is removed
sub BoxTrapper_messageaction {    ## no critic qw(ProhibitExcessComplexity)
    my ( $account, $logdate, $queuefile, $action ) = @_;

    return if !_role_is_enabled();

    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $error = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        $Cpanel::CPERROR{'boxtrapper'} = $error;
        print $error;
        return;
    }

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my $html_safe_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);
    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', $html_safe_account ) . "\n";
        return;
    }

    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    if ( !$emaildir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', $html_safe_account ) . "\n";
        return;
    }

    my @ACTIONS = split( /\,/, $action );
    if ( !@ACTIONS ) {
        Cpanel::Logger::cplog( 'Missing arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my ( $headersref, $primary_bodyfh, $email );
    if ($queuefile) {
        $queuefile =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
        ( $headersref, $primary_bodyfh ) = BoxTrapper_extract_headers_return_bodyglobref( $emaildir . '/boxtrapper/queue/' . $queuefile );
        $email = BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', $headersref ) );
        $email = Cpanel::Encoder::Tiny::safe_html_encode_str($email);
        $email =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    }

    foreach my $action (@ACTIONS) {
        if ( $action eq 'deliverall' && !-e $emaildir . '/boxtrapper/verifications/' . $email ) {
            $action = 'deliver';
        }

        if ( $action eq 'whitelist' ) {
            print $locale->maketext( 'The following email address was added to your whitelist: [_1]', $email ) . "<br/>\n";
            BoxTrapper_addaddytolist( 'white', $email, $emaildir );
        }
        elsif ( $action eq 'blacklist' ) {
            print $locale->maketext( 'The following email address was added to your blacklist: [_1]', $email ) . "<br/>\n";
            BoxTrapper_addaddytolist( 'black', $email, $emaildir );
        }
        elsif ( $action eq 'ignorelist' ) {
            print $locale->maketext( 'The following email address was added to your ignore list: [_1]', $email ) . "<br/>\n";
            BoxTrapper_addaddytolist( 'ignore', $email, $emaildir );
        }
        elsif ( $action eq 'deliverall' ) {
            my $verflock = Cpanel::SafeFile::safeopen( \*MSGIDS, '<', $emaildir . '/boxtrapper/verifications/' . $email );
            if ( !$verflock ) {
                $logger->warn("Could not read from $emaildir/boxtrapper/verifications/$email");
                return;
            }
            my @failed_removal;
            my @msgids;
            while ( my $msgidr = <MSGIDS> ) {
                chomp $msgidr;
                next if !-e $emaildir . '/boxtrapper/queue/' . $msgidr . '.msg';
                my $queuefile = $msgidr . '.msg';
                my ( $headersref, $bodyfh ) = BoxTrapper_extract_headers_return_bodyglobref( $emaildir . '/boxtrapper/queue/' . $msgidr . '.msg' );
                if ( !@{$headersref} ) {
                    close($bodyfh);
                    BoxTrapper_clog( 2, $emaildir, "Skipping deliverall of message $msgidr as it is not in the queue (from a deliverall)" );
                    next;
                }
                push @{$headersref}, "X-BoxTrapper-Queue: released via web action: deliverall\n";

                if ( BoxTrapper_delivermessage( $account, 1, $emaildir, $emaildeliverdir, $headersref, $bodyfh ) ) {
                    BoxTrapper_clog( 3, $emaildir, "delivered message $emaildir/boxtrapper/queue/$queuefile from queue via messageaction: deliverall" );
                }
                else {
                    BoxTrapper_clog( 2, $emaildir, "Unable to deliver $emaildir/boxtrapper/queue/$queuefile from queue: $!" );
                    warn "Unable to deliver messages due to I/O error";
                    next;
                }

                if ( unlink $emaildir . '/boxtrapper/queue/' . $msgidr . '.msg' ) {
                    push @msgids, $msgidr;
                }
                else {
                    push @failed_removal, $msgidr;
                    BoxTrapper_clog( 2, $emaildir, "Unable to remove delivered message ${msgidr}.msg from queue: $!" );
                    Cpanel::Logger::cplog( "Unable to unlink $emaildir/boxtrapper/queue/${msgidr}.msg: $!", 'warn', __PACKAGE__, 1 );
                }
            }
            Cpanel::SafeFile::safeclose( \*MSGIDS, $verflock );
            if (@msgids) {
                BoxTrapper_removefromsearchdb( $emaildir, \@msgids );
            }
            if (@failed_removal) {
                print "Unable to remove some queued messages. Check the BoxTrapper log for more details.<br />\n";
                my $verflock = Cpanel::SafeFile::safeopen( \*MSGIDS, '>', $emaildir . '/boxtrapper/verifications/' . $email );
                if ( !$verflock ) {
                    $logger->warn("Could not write to $emaildir/boxtrapper/verifications/$email");
                    return;
                }
                print MSGIDS join( "\n", @failed_removal ) . "\n";
                Cpanel::SafeFile::safeclose( \*MSGIDS, $verflock );
            }
            else {
                if ( unlink $emaildir . '/boxtrapper/verifications/' . $email ) {
                    print "Queued messages from $email delivered.<br />\n";
                }
                else {
                    Cpanel::Logger::cplog( "Failed to unlink $emaildir/boxtrapper/verifications/$email: $!", 'warn', __PACKAGE__, 1 );
                    print "Queued messages from $email delivered, but there was a problem.<br />\n";
                }
            }
        }
        elsif ( $action eq 'deliver' ) {
            if ( !-e $emaildir . '/boxtrapper/queue/' . $queuefile ) {
                print "No message found to deliver.<br />\n";
                return;
            }
            print $locale->maketext( 'Queued message from “[_1]” was delivered.', $email ) . "\n";

            push @{$headersref}, "X-BoxTrapper-Queue: released via web action: deliver\n";
            if ( BoxTrapper_delivermessage( $account, 1, $emaildir, $emaildeliverdir, $headersref, $primary_bodyfh ) ) {
                BoxTrapper_clog( 3, $emaildir, "delivered message $emaildir/boxtrapper/queue/$queuefile from queue via messageaction: deliver" );
            }
            else {
                BoxTrapper_clog( 2, $emaildir, "Unable to deliver $emaildir/boxtrapper/queue/$queuefile from queue: $!" );
                warn "Unable to deliver messages due to I/O error";
                return;
            }

            if ( unlink $emaildir . '/boxtrapper/queue/' . $queuefile ) {
                BoxTrapper_removefromsearchdb( $emaildir, $queuefile );
            }
            else {
                BoxTrapper_clog( 2, $emaildir, "Unable to remove delivered message $emaildir/boxtrapper/queue/$queuefile from queue: $!" );
                Cpanel::Logger::cplog( "Unable to unlink $emaildir/boxtrapper/queue/$queuefile: $!", 'warn', __PACKAGE__, 1 );
            }
        }
        elsif ( $action eq 'delete' ) {
            if ( !-e $emaildir . '/boxtrapper/queue/' . $queuefile ) {
                print "No message found to delete.<br />\n";
                return;
            }
            if ( unlink $emaildir . '/boxtrapper/queue/' . $queuefile ) {
                print $locale->maketext( 'Queued message from “[_1]” was deleted.', $email ) . "\n";
                BoxTrapper_clog( 2, $emaildir, "Deleted $queuefile from $email" );
                BoxTrapper_removefromsearchdb( $emaildir, $queuefile );
            }
            else {
                print "Unable to delete message.<br />\n";
                Cpanel::Logger::cplog( "Failed to unlink $emaildir/boxtrapper/queue/$queuefile: $!", 'warn', __PACKAGE__, 1 );
                BoxTrapper_clog( 2, $emaildir, "Unable to delete ${emaildir}/boxtrapper/queue/${queuefile}: $!" );
            }
        }
        elsif ( $action eq 'deleteall' ) {
            if ( !-e $emaildir . '/boxtrapper/verifications/' . $email ) {
                print "No verification list found for $email.<br />\n";
                return;
            }
            my $verflock = Cpanel::SafeFile::safeopen( \*MSGIDS, $emaildir . '/boxtrapper/verifications/' . $email );
            if ( !$verflock ) {
                $logger->warn("Could not read from $emaildir/boxtrapper/verifications/$email");
                return;
            }
            my @msgids;
            while ( my $msgidr = <MSGIDS> ) {
                chomp $msgidr;
                if ( -e $emaildir . '/boxtrapper/queue/' . $msgidr . '.msg' ) {
                    if ( unlink $emaildir . '/boxtrapper/queue/' . $msgidr . '.msg' ) {
                        BoxTrapper_clog( 2, $emaildir, "Deleted ${msgidr}.msg from $email" );
                        push @msgids, $msgidr;
                    }
                    else {
                        Cpanel::Logger::cplog( "Failed to unlink $emaildir/boxtrapper/queue/${msgidr}.msg: $!", 'warn', __PACKAGE__, 1 );
                        BoxTrapper_clog( 2, $emaildir, "Unable to delete ${emaildir}/boxtrapper/queue/${msgidr}.msg: $!" );
                    }
                }
            }
            Cpanel::SafeFile::safeclose( \*MSGIDS, $verflock );
            unlink $emaildir . '/boxtrapper/verifications/' . $email;
            print "Queued messages from $email removed.<br />\n";
            BoxTrapper_removefromsearchdb( $emaildir, \@msgids );
        }
    }
    if ($primary_bodyfh) { close($primary_bodyfh); }

    return;
}

# DEPRECATED: Remove once API 1 is removed
sub BoxTrapper_multimessageaction {
    return if !_role_is_enabled();
    return if !Cpanel::hasfeature('boxtrapper');
    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $error = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        $Cpanel::CPERROR{'boxtrapper'} = $error;
        print $error;
        return;
    }

    local $Cpanel::IxHash::Modify = 'none';
    my $account           = $Cpanel::FORM{'account'};
    my $action            = $Cpanel::FORM{'multimsg'};
    my $html_safe_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    if ( !$account ) {
        Cpanel::Logger::cplog( 'Missing arguments', 'warn', __PACKAGE__, 1 );
        return;
    }

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', $html_safe_account ) . "\n";
        return;
    }

    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );

    my @msgids;

    foreach my $msg_id ( sort keys %Cpanel::FORM ) {
        next if ( $msg_id !~ m/^msgid\d+/ || !$Cpanel::FORM{$msg_id} );
        my $queuefile = $Cpanel::FORM{$msg_id};
        $queuefile =~ s/\///g;
        next if ( !$queuefile || !-e $emaildir . '/boxtrapper/queue/' . $queuefile );

        my ( $HEADERS, $bodyfh ) = BoxTrapper_extract_headers_return_bodyglobref( $emaildir . '/boxtrapper/queue/' . $queuefile );
        my $email = BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', $HEADERS ) );
        if ( $action eq 'whitelistall' ) {
            BoxTrapper_addaddytolist( 'white', $email, $emaildir );

            push @{$HEADERS}, "X-BoxTrapper-Queue: released via web multiaction: whitelistall\n";

            if ( BoxTrapper_delivermessage( $account, 1, $emaildir, $emaildeliverdir, $HEADERS, $bodyfh ) ) {
                BoxTrapper_clog( 3, $emaildir, "delivered message $emaildir/boxtrapper/queue/$queuefile from queue via multimessageaction: whitelistall" );
            }
            else {
                BoxTrapper_clog( 2, $emaildir, "Unable to deliver $emaildir/boxtrapper/queue/$queuefile from queue: $!" );
                warn "Unable to deliver messages due to I/O error";
                next;
            }
            if ( unlink $emaildir . '/boxtrapper/queue/' . $queuefile ) {
                push @msgids, $queuefile;
                print $locale->maketext( 'Queued message from “[_1]” was delivered.', $email ) . "<br />\n";
            }
        }
        elsif ( $action eq 'deleteall' ) {
            if ( unlink $emaildir . '/boxtrapper/queue/' . $queuefile ) {
                push @msgids, $queuefile;
                print $locale->maketext( 'Queued message from “[_1]” was deleted.', $email ) . "<br />\n";
                BoxTrapper_clog( 2, $emaildir, "Deleted $queuefile from $email" );
            }
        }
        if ($bodyfh) { close($bodyfh); }
    }
    BoxTrapper_removefromsearchdb( $emaildir, \@msgids );

    return;
}

sub BoxTrapper_resetmsg {
    my ( $account, $message ) = @_;

    return if !_role_is_enabled();

    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $error = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        $Cpanel::CPERROR{'boxtrapper'} = $error;
        print $error;
        return;
    }

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', Cpanel::Encoder::Tiny::safe_html_encode_str($account) ) . "\n";
        return;
    }
    $message =~ s/$Cpanel::Regex::regex{'forwardslash'}//g;
    $message =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    if ( -e $emaildir . '/.boxtrapper/forms/' . $message ) {
        unlink( $emaildir . '/.boxtrapper/forms/' . $message );
    }

    return;
}

sub BoxTrapper_saveconf {    ## no critic qw(ProhibitManyArgs  ProhibitExcessComplexity)
    my ( $account, $froms, $queuetime, $autowhitelist, $fromname, $min_spam_score_deliver, $whitelist_by_assoc ) = @_;

    return if !_role_is_enabled();

    return if !Cpanel::hasfeature('boxtrapper');
    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $error = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        $Cpanel::CPERROR{'boxtrapper'} = $error;
        print $error;
        return;
    }

    my $esc_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);
    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', $esc_account ) . "\n";
        return;
    }
    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    if ( $emaildir eq "" || $emaildeliverdir eq "" ) {
        print $locale->maketext( 'Email directory for account “[_1]” does not exist.', $esc_account ) . "\n";
        return;
    }
    $froms =~ s/\n//g;
    $froms =~ s/^\s+//;
    $froms =~ s/\s+$//;
    my @bad_froms = grep { !Cpanel::Validate::EmailCpanel::is_valid($_) && !Cpanel::Validate::EmailLocalPart::is_valid($_) } split( /\s*,\s*/, $froms );
    if (@bad_froms) {
        print $locale->maketext( 'Email address list contains one or more invalid email addresses: [_1].', Cpanel::Encoder::Tiny::safe_html_encode_str( join( ', ', @bad_froms ) ) );
        return;
    }
    $queuetime =~ s/[\r\n\f]//g;
    $fromname  =~ s/[\r\n\f]//g;
    $fromname  =~ s/\"//g;

    if ( $queuetime !~ /^[0-9]+$/ or $queuetime <= 0 ) {
        print $locale->maketext('Number of days to keep logs must be a positive integer.');
        return;
    }

    if ( !defined $min_spam_score_deliver or $min_spam_score_deliver eq '' ) {
        $min_spam_score_deliver = -25;    # The score is stored without decimal for compat with SA
    }
    elsif ( $min_spam_score_deliver !~ /^-?[0-9]+(?:\.[0-9]+)?$/ ) {
        print $locale->maketext( 'Invalid value for minimum spam score: “[_1]”.', Cpanel::Encoder::Tiny::safe_html_encode_str($min_spam_score_deliver) );
        return;
    }
    else {
        $min_spam_score_deliver *= 10;    # The score is stored without decimal for compat with SA
    }
    $min_spam_score_deliver = int $min_spam_score_deliver;    # Zero is acceptable

    my $conflock = Cpanel::SafeFile::safeopen( \*CF, '>', $emaildir . '/boxtrapper.conf' );
    if ( !$conflock ) {
        $logger->warn("Could not write to $emaildir/boxtrapper.conf");
        return;
    }
    print CF "froms=${froms}\n";
    print CF "stale-queue-time=${queuetime}\n";
    print CF "fromname=${fromname}\n";
    print CF "min_spam_score_deliver=${min_spam_score_deliver}\n";
    print CF "whitelist_by_assoc=" . ( defined $whitelist_by_assoc ? int $whitelist_by_assoc : 1 ) . "\n";
    Cpanel::SafeFile::safeclose( \*CF, $conflock );

    if ( $autowhitelist && -e $emaildir . '/.boxtrapperautowhitelistdisable' ) {
        unlink( $emaildir . '/.boxtrapperautowhitelistdisable' );
    }
    elsif ( !$autowhitelist ) {
        my $AW;
        if ( !open( $AW, '>', $emaildir . '/.boxtrapperautowhitelistdisable' ) ) {
            print $locale->maketext('The system failed to disable the [asis,BoxTrapper] automatic whitelist.');
            return;
        }
        close($AW);
    }
    print $locale->maketext('The system saved your changes.') . "\n";

    return;
}

sub BoxTrapper_showautowhitelist {
    my $account = shift;

    return if !_role_is_enabled();

    my $locale      = Cpanel::Locale->get_handle();
    my $esc_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', $esc_account ) . "\n";
        return;
    }
    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    if ( $emaildir eq '' || $emaildeliverdir eq '' ) {
        print $locale->maketext( 'Email directory for account “[_1]” does not exist.', $esc_account ) . "\n";
        return;
    }
    if ( !-e $emaildir . '/.boxtrapperautowhitelistdisable' ) {
        $Cpanel::CPVAR{'showautowhitelist_checked'} = 1;
        print 'checked="checked"';
    }
    else {
        $Cpanel::CPVAR{'showautowhitelist_checked'} = 0;
    }

    return;
}

sub BoxTrapper_showemails {
    my (@args) = @_;

    return if !_role_is_enabled();

    my $conf = _get_conf_by_acct(@args);

    print Cpanel::Encoder::Tiny::safe_html_encode_str( $conf->{'froms'} );

    return;
}

=head2 BoxTrapper_showlog(DATE, ACCOUNT, OPTS)

Fetches the BoxTrapper log for the specific date and account.

=head3 NOTES

This is the API 1 implementation and is used internally
by the UAPI call Cpanel::API::BoxTrapper::get_log.

=head3 ARGUMENTS

=over

=item DATE - number

Linux timestamp for the date you are requesting logs for.

=item ACCOUNT - string

Either a cPanel user name or an email account. The account is ignored for Webmail and gets auto-populated with the logged-in user email account.

=item OPTS - hashref

=over

=item api1 - Boolean

Provides error handing and output using API 1 semantics. (print, Cpanel::CPERROR)

=item uapi - Boolean

Provide error handling by throwing exceptions

=item validate - Boolean

Enabled ownership and existence validation for the email account. Defaults to not performing the validation.

=back

=back

=head3 RETURNS

In UAPI mode this method returns a hash with the following properties:

=over

=item date - number

Linux timestamp representation of the date requested. This will be the same as the date argument passed in.

=item path - string

Path to the logfile for the date requests. The file may not exist or be empty.

=item lines - string[]

The lines read from the log file. The lines have their trailing linefeeds stripped. The lines array is empty if the logfile does not exist or if there are no log lines in the file yet.

=back

When in API 1 mode, it will return undef on any error and 1 for success.

When in UAPI mode, all errors are thrown as exceptions.

=head3 SIDE EFFECTS

Note that in API 1 mode there are several possible side effects:

=over

=item There may be prints to STDOUT

=item There may be values set to $Cpanel::CPERROR{'boxtrapper'}

=back

=cut

sub BoxTrapper_showlog {
    my ( $logdate, $account, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    return if !_role_is_enabled();

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    elsif ( !$account ) {
        _handle_error(
            Cpanel::Exception::create( 'InvalidParameter', 'You must define the “[_1]” parameter.', [qw(account)] ),
            $opts,
        );
        return;
    }

    $logdate = time() if !defined $logdate || $logdate !~ m/^\d+$/;
    eval { Cpanel::Validate::Time::epoch_or_die($logdate) };
    if ( my $exception = $@ ) {
        _handle_error( $exception, $opts );
        return;
    }

    my ($homedir) = BoxTrapper_getaccountinfo( $account, undef, $opts );
    if ( !$homedir ) {
        _handle_error(
            locale()->maketext( "The system failed to locate a home directory for the account “[_1]”.", Cpanel::Encoder::Tiny::safe_html_encode_str($account) ),
            $opts
        );
        return;
    }

    my ($emaildir) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        $Cpanel::BoxTrapper::CORE::SKIP_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::SKIP_CREATE_EMAIL_DIRS,
        $opts
    );

    if ( $emaildir eq '' ) {
        _handle_error(
            locale()->maketext(
                'The system cannot get the [asis,BoxTrapper] log because the email directory for account “[_1]” does not exist.',
                Cpanel::Encoder::Tiny::safe_html_encode_str($account)
            ),
            $opts
        );
        return;
    }

    my @lines;
    my ( $mon, $mday, $year ) = BoxTrapper_nicedate($logdate);
    my $path = $emaildir . '/boxtrapper/log/' . $mon . '-' . $mday . '-' . $year . '.log';

    return {
        path  => '',
        lines => \@lines,
        date  => $logdate,
    } if !-e $path && $opts->{uapi};    # prevents spew to STDERR for missing files

    if ( my $lock = Cpanel::SafeFile::safeopen( my $clog, '<', $path ) ) {
        while (<$clog>) {
            if ( $opts->{uapi} ) {
                chomp;
                push @lines, $_;
            }
            else {
                print Cpanel::Encoder::Tiny::safe_html_encode_str($_);
            }
        }
        Cpanel::SafeFile::safeclose( $clog, $lock );
    }
    elsif ( $! == _ENOENT() ) {

        # We don't want to throw an error for UAPI just because there are no
        # log entries. It should just return a empty log for that day.
        if ( $opts->{api1} ) {
            _handle_error( locale()->maketext( "There are no [asis,BoxTrapper] log entries for [datetime,_1,datetime_format_short]", $logdate ), $opts );
        }
    }
    else {
        _handle_error( locale()->maketext( "The system failed to open the log file “[_1]” due to the error: “[_2]”", $path, $! ), $opts );
    }

    return {
        path  => $path,
        lines => \@lines,
        date  => $logdate,
    } if $opts->{uapi};

    return 1;
}

=head2 _fetch_queued_message_path_for_account(EMAIL, FILE, OPTS) [PRIVATE]

Calculates the full path to the requested message.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address to retrieve the message for.

=item FILE - string

The message filename you want to retrieve.

=item OPTS - hash

Fine grain control of how the API reports success and failure for UAPI mode or for API 1 mode.

=back

=head3 RETURNS

string - the path to the theoretical location for the blocked email message.

=head3 THROWS

=over

=item When the email account does not exist.

=item When the email account is not owned by the logged in cPanel user.

=back

=cut

sub _fetch_queued_message_path_for_account {
    my ( $account, $queuefile, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    $queuefile =~ s/\.\.//g;
    $queuefile =~ s/\///g;
    my ($homedir) = BoxTrapper_getaccountinfo( $account, undef, $opts );
    if ( !$homedir ) {
        _handle_error(
            locale()->maketext( 'The requested email account, [_1], is invalid.', $account ),
            $opts,
        );
        return;
    }

    my ($emaildir) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        $Cpanel::BoxTrapper::CORE::SKIP_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::SKIP_CREATE_EMAIL_DIRS,
        $opts
    );
    if ( !$emaildir ) {
        _handle_error(
            locale()->maketext( 'The system failed to access the email account “[_1]”.', $account ),
            $opts,
        );
        return;
    }

    return ( $emaildir . '/boxtrapper/queue/' . $queuefile );
}

# TODO TSA-267 - Add POD/tests

sub get_queued_message_path ( $account, $file_name, $opts = {} ) {
    my $appname = $opts->{appname} || $Cpanel::appname;

    if ( !$appname ) {
        require Cpanel::App;
        $appname = $Cpanel::App::appname;
    }

    local $Cpanel::appname = $appname;
    return _fetch_queued_message_path_for_account( $account, $file_name, { uapi => 1 } );
}

sub BoxTrapper_downloadmessage {
    my ( $account, $logdate, $queuefile ) = @_;

    return if !_role_is_enabled();

    my $path = _fetch_queued_message_path_for_account( $account, $queuefile ) or return;
    return if !$path;
    if ( open( my $qf, '<', $path ) ) {
        local $/;
        print readline($qf);
    }

    return;
}

=head2 get_message(EMAIL, FILE, OPTS)

Retrieve up to the first 200 lines of a blocked email message from the BoxTrapper queue.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address to retrieve the message for.

=item FILE - string

The message filename you want to retrieve.

=item OPTS - hash

Fine grain control of how the API reports success and failure for UAPI mode or for API 1 mode.

=back

=head3 RETURNS

=over

=item 'uapi' mode - string

Up to the first 200 lines of the blocked email message when in UAPI mode.

=item 'api1' mode - nothing

=back

=head3 THROWS

=over

=item When the email account does not exist.

=item When the email account is not owned by the logged-in cPanel user.

=item When the requested message does not exist.

=back

=head3 SIDE EFFECTS

In 'api1' mode this function prints output to STDOUT for both success and errors and updates the $Cpanel::CPERROR{'boxtrapper'} global.

=cut

sub get_message {
    my ( $account, $queuefile, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    return if !_role_is_enabled();

    my $path = _fetch_queued_message_path_for_account( $account, $queuefile, $opts ) or return;
    if ( $path && !-e $path ) {
        _handle_error(
            locale()->maketext(
                'The requested message “[_1]” does not exist.',
                $queuefile
            ),
            $opts
        );
        return;
    }

    if ( $path && !-r $path ) {
        _handle_error(
            locale()->maketext(
                'The requested message “[_1]” at the path “[_2]” is not readable.',
                $queuefile,
                $path,
            ),
            $opts
        );
        return;
    }

    require Cpanel::Buffer::Line;
    my $buffer = Cpanel::Buffer::Line->new();

    my $lines = 0;
    my @lines;
    if ( my $lock = Cpanel::SafeFile::safeopen( my $QFH, '<', $path ) ) {
        while ( my $line = $buffer->readline($QFH) ) {
            $lines++;
            last if ( $lines > $MAX_EMAIL_LINES_TO_PRINT );
            if ( $opts->{api1} ) {

                # DEPRECATED: Remove this branch once api 1 is removed
                chomp($line);
                print Cpanel::Encoder::Tiny::safe_html_encode_str($line) . "\n";
            }
            else {
                push @lines, $line;
            }
        }
        Cpanel::SafeFile::safeclose( $QFH, $lock );
    }

    return join( '', @lines ) if $opts->{uapi};
    return;
}

sub BoxTrapper_showmessage {
    my ( $account, $logdate, $queuefile ) = @_;
    return get_message( $account, $queuefile );
}

=head2 list_queue(DATE, EMAIL, OPTS)

=head3 ARGUMENTS

=over

=item DATE - UNIX timestamp

The day to query. Defaults to today. Ignored if a filter is passed.

=item EMAIL - string

Email address to list the blocked messages for.

=item OPTS - hashref

=over

=item api1 - boolean

Provides error handing and output using API 1 semantics. (print, Cpanel::CPERROR)

=item uapi - boolean

Provide error handling by throwing exceptions

=item validate - boolean

Enabled ownership and existence validation for the email account. Defaults to not performing the validation.

=item filters - C<Cpanel::Args::Filter> array.

List of filters if any provided by the caller. Note, only the first filter for a header or body is applied internally. Other filters are expected to be applied by the caller. These provide special optimized filter that are faster then the build in API post filter mechanics.

=back

=back

=head3 RETURNS

List with the following positional elements:

=over

=item MESSAGES - array ref

Messages that match the filter.

=item COUNT - number

Number of messages before the filter was applied.

=back

=head3 THROWS

=over

=item When the BoxTrapper directory structure cannot be created.

=item When the BoxTrapper search database cannot be opened.

=item When more than one 'body' filter is requested.

=item When the email account is invalid.

=item When the email account is not owned by the logged in user.

=item When the caller passes a filter that is not a C<Cpanel::Args::Filter> object.

=back

=cut

sub list_queue {
    my ( $logdate, $account, $opts ) = @_;

    return if !_role_is_enabled();

    if ( !defined($opts) || ref $opts ne 'HASH' ) {
        $opts = { api1 => 1 };
    }
    elsif ( !exists( $opts->{'api1'} ) && !exists( $opts->{'uapi'} ) ) {
        $opts->{'api1'} = 1;
    }

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    $logdate = time() if !defined $logdate || $logdate !~ m/^\d+$/;

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo( $account, undef, $opts );
    if ( !$homedir ) {
        _handle_error(
            locale()->maketext( 'The system failed to locate the email account “[_1]”.', $account ),
            $opts
        );
        return;
    }

    my ($emaildir) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        $Cpanel::BoxTrapper::CORE::SKIP_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::SKIP_CREATE_EMAIL_DIRS,
        $opts
    );
    if ( !$emaildir ) {
        _handle_error(
            locale()->maketext( 'The system failed to locate the email account “[_1]”.', $account ),
            $opts
        );
        return;
    }

    my ( $messages, $count, $fetched ) = ( [], 0, 0 );
    if ( $opts->{filters} && ref $opts->{filters} eq 'ARRAY' ) {
        foreach my $filter ( @{ $opts->{filters} } ) {

            my $is_filter = eval { $filter->isa("Cpanel::Args::Filter") };
            if ( !$is_filter ) {
                _handle_error( locale()->maketext('The system requires a [asis,Cpanel::Args::Filter] instance to perform filtering operations.'), $opts );
                next;
            }

            if ( grep { $filter->column() eq $_ } qw(from subject) ) {
                if ( $filter->type() ne 'contains' ) {
                    _handle_error( locale()->maketext( 'The system does not support a “[_1]” filter using the “[_2]” operator.', $filter->column(), $filter->type() ), $opts );
                    return;
                }

                if ( !$fetched ) {
                    ( $messages, $count ) = _fetch_by_header( $emaildir, $filter, $opts );
                    $fetched = 1;
                    $filter->{handled} = 1;
                }
            }
            elsif ( $filter->column() eq 'body' ) {
                if ( $filter->type() ne 'contains' ) {
                    _handle_error( locale()->maketext( 'The system does not support a “[_1]” filter using the “[_2]” operator.', 'body', $filter->type() ), $opts );
                    return;
                }

                if ( !$fetched ) {
                    ( $messages, $count ) = _fetch_by_body( $emaildir, $filter, $opts );
                    $fetched = 1;
                    $filter->{handled} = 1;
                }
                else {
                    _handle_error( locale()->maketext( 'The system does not support additional “[_1]” filters. To filter the “[_1]”, do not include any other filters.', 'body' ), $opts );
                }
            }
        }
    }
    if ( !$fetched ) {
        ( $messages, $count ) = _fetch( $emaildir, $logdate, $opts );
    }

    # Apply a default sort if no other sort is requested.
    if ( !$opts->{sort} ) {
        $messages = [ sort { $a->{'time'} <=> $b->{'time'} } @$messages ];
    }

    return ( $messages, $count );
}

=head2 list_email_template($account, $template)

Get the contents of a BoxTrapper message template for an account.

=head3 ARGUMENTS

=over

=item account - string

Account the template is for.

=item template - string

One of:

=over

=item * blacklist

=item * returnverify

=item * verifyreleased

=item * verify

=back

=back


=head3 RETURNS

Returns the full contents of the requested template string.

=head3 THROWS

=over

=item When the requested email account is not owned by the cPanel user

=item When the requested email account does not exist.

=item When the template file cannot be opened or read from.

=item When the template specified is invalid.

=back

=cut

sub list_email_template {
    my ( $account, $template ) = @_;

    _assert_feature_enabled();
    _validate_template($template);

    $account = _get_account($account);
    my ( $homedir, $emaildir ) = _list_account_directories($account);
    my $path = "${emaildir}/.boxtrapper/forms/${template}.txt";

    if ( !-e $path ) {
        my $src = DEFAULT_TEMPLATE_PATH . "/${template}.txt";
        _copy_file( $src, $path );
    }

    require Cpanel::SafeFile;
    if ( my $lock = Cpanel::SafeFile::safeopen( my $fh, "<", $path ) ) {

        my $contents = '';
        my $bytes    = read( $fh, $contents, MAX_TEMPLATE_SIZE );

        Cpanel::SafeFile::safeclose( $fh, $lock );

        if ( !defined($bytes) ) {
            die Cpanel::Exception::create( "IO::FileReadError", [ error => $!, path => $path ] ) if $!;
            die Cpanel::Exception::create(
                "IO::FileReadError",
                [
                    error => 'The system was unable to read the template file.',
                    path  => $path
                ]
            );
        }

        return $contents;

    }
    else {

        die Cpanel::Exception::create(
            'IO::FileOpenError',
            'The system could not open the “[_1]” template file.',
            [$template]
        );

    }
}

=head2 _get_search_db(DIR, OPTS) [PRIVATE]

Retrieves the BoxTrapper search database that contains a map from
the blocked email's id to the various email headers for that email mail.
This database can be used to accelerate filter of the list of blocked
emails by reducing the need to open each file to check the headers.

=head3 ARGUMENTS

=over

=item DIR - string

Path to the email directory for a specific email account.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

Hashref where the keys are the id for an email that was blocked by BoxTrapper and the value are a hash with the following structure:

=over

=item from - array

List of 'from' addresses from the email header.

=item subject - array

List of 'subject' lines from the email header.

=back

=head3 THROWS

=over

=item When the BoxTrapper directory structure cannot be created.

=item When the BoxTrapper search database cannot be opened.

=back

=cut

sub _get_search_db {
    my ( $emaildir, $opts ) = @_;
    my $search_db_path = _ensure_boxtrapper_search_db( $emaildir, $opts );
    my $search_db_lock = Cpanel::SafeFile::safeopen( my $SDB, '+<', $search_db_path );
    if ( !$search_db_lock ) {
        _handle_warn(
            locale()->makextext(
                'The system failed to open the [asis,BoxTrapper] search database: [_1]',
                $search_db_path
            ),
            "The system failed to open the BoxTrapper search database: search_db_path",
            $opts
        );
        return;
    }

    my $search_db = eval { _loadsearchdb($SDB) };
    Cpanel::SafeFile::safeclose( $SDB, $search_db_lock );

    return $search_db;
}

=head2 _fetch_by_header(DIR, FILTER, OPTS)

Fetch blocked messages that match the requested header filter.

=head3 ARGUMENTS

=over

=item DIR - string

Path to the email directory for a specific email account.

=item FILTER - C<Cpanel::Args::Filter>

A filter for one of the header fields:

=over

=item * from

=item * subject

=back

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

List with the following positional elements:

=over

=item MESSAGES - array ref

Messages that match the filter.

=item COUNT - number

Number of messages before the filter was applied.

=back

=head3 THROWS

=over

=item When the BoxTrapper directory structure cannot be created.

=item When the BoxTrapper search database cannot be opened.

=back

=cut

sub _fetch_by_header {
    my ( $emaildir, $filter, $opts ) = @_;

    my @messages;
    my @invalid_search_db_entries;

    my $count = 0;
    my $term  = $filter->term();

    if ( my $searchregex = eval { qr/$term/im; } ) {
        my $column    = $filter->column();
        my $search_db = _get_search_db( $emaildir, $opts );

        foreach my $message ( keys %$search_db ) {
            my $column_data = $search_db->{$message}{$column} || [''];
            $count++;
            next if ref $column_data ne 'ARRAY';

            foreach my $value (@$column_data) {
                if ( $value =~ tr/\&// ) {
                    $value = Cpanel::Encoder::Tiny::safe_html_decode_str($value);
                }
                next if !grep { m/$searchregex/im } @$column_data;
                my $path = $emaildir . '/boxtrapper/queue/' . $message . '.msg';
                if ( -e $path ) {    # Don't add message that doesn't exist to results
                    my $mtime = ( $message =~ tr/-// ) ? ( split( /\-/, $message ) )[1] : ( stat(_) )[9];

                    push @messages, _build_entry(
                        $mtime,
                        $message . '.msg',
                        $path,
                        $opts,
                    );
                }
                else {
                    $count--;
                    push @invalid_search_db_entries, $message;
                }
            }
        }
    }

    # Delete invalid entries from search.db
    if (@invalid_search_db_entries) {
        BoxTrapper_removefromsearchdb( $emaildir, \@invalid_search_db_entries );
    }

    return ( \@messages, $count );
}

=head2 _fetch_by_body(DIR, FILTER, OPTS)

Fetch blocked messages that match the body filter.

=head3 ARGUMENTS

=over

=item DIR - string

Path to the email directory for a specific email account.

=item FILTER - C<Cpanel::Args::Filter>

A filter for body of the block emails.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

List with the following positional elements:

=over

=item MESSAGES - array ref

Messages that match the filter.

=item COUNT - number

Number of messages before the filter was applied.

=back

=head3 THROWS

=over

=item When the message file cannot be opened.

=back

=cut

sub _fetch_by_body {
    my ( $emaildir, $filter, $opts ) = @_;
    my @messages;
    my $count = 0;

    my $term = $filter->term();
    if ( my $searchregex = eval { qr/$term/im; } ) {
        my $dir = $emaildir . '/boxtrapper/queue';
        if ( _opendir_if_exists_or_warn( my $qdir, $dir ) ) {
            while ( my $queuefile = readdir($qdir) ) {
                next if ( $queuefile =~ /^\./ || $queuefile =~ /\.lock$/ );
                $count++;
                my $file_to_search = "${dir}/${queuefile}";
                my ( $bodyref, $mtime ) = _extractbody_scalarref_mtime( $file_to_search, 1024 * 256 );
                if ( $$bodyref =~ m/$searchregex/im ) {
                    push @messages, _build_entry(
                        $mtime,
                        $queuefile,
                        $file_to_search,
                        $opts,
                    );
                }
            }
        }
    }

    return ( \@messages, $count );
}

=head2 _fetch(DIR, DATE, OPTS)

Fetch blocked messages that were received on the same day as the passed date.

=head3 ARGUMENTS

=over

=item DIR - string

Path to the email directory for a specific email account.

=item DATE - UNIX timestamp

Limit the query to the day part of this date.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

List with the following positional elements:

=over

=item MESSAGES - array ref

Messages that match the filter.

=item COUNT - number

Number of messages before the filter was applied.

=back

=cut

sub _fetch {
    my ( $emaildir, $logdate, $opts ) = @_;

    my $mail_queue_dir = "${emaildir}/boxtrapper/queue";
    my @QDIR;
    if ( _opendir_if_exists_or_warn( my $qdir, $mail_queue_dir ) ) {
        @QDIR = grep( !/^\./, readdir($qdir) );
    }

    my ( $mon, $mday, $year ) = BoxTrapper_nicedate($logdate);
    my $mintime = Time::Local::timelocal_modern( 0,  0,  0,  $mday, $mon - 1, $year );
    my $maxtime = Time::Local::timelocal_modern( 59, 59, 23, $mday, $mon - 1, $year );

    my @messages;
    my $count = 0;

    foreach my $queuefile (@QDIR) {
        $count++;
        my $mtime = ( $queuefile =~ tr/-// ) ? ( split( /[\-\.]/, $queuefile ) )[1] : ( stat( $mail_queue_dir . '/' . $queuefile ) )[9];

        # Retrieve the creation from the filename if possible (otherwise fallback to mtime) to avoid the problem in case 47038
        if ( $mtime >= $mintime && $mtime < $maxtime ) {
            push @messages, _build_entry(
                $mtime,
                $queuefile,
                $emaildir . '/boxtrapper/queue/' . $queuefile,
                $opts,
            );
        }
    }
    return ( \@messages, $count );
}

=head2 _build_entry(MTIME, FILE, PATH)

Build an entry for a specific blocked email.

=head3 ARGUMENTS

=over

=item MTIME - UNIX timestamp

The time the file was last modified.

=item FILE - string

The unique id for the block email.

=item PATH - string

The complete filesystem path to the file for the blocked email.

=back

=head3 RETURNS

A hash reference with the following format:

=over

=item from - string

From header for the email.

=item subject - string

Subject header for the email.

=item queuefile - string

File name for the queued email.

=item time - UNIX timestamp

Time when the email was blocked.

=back

=cut

sub _build_entry {
    my ( $mtime, $file, $path, $opts ) = @_;

    my $data = {
        time      => $mtime,
        queuefile => $file,
        from      => '',
        subject   => '',
    };

    eval {
        my $rHEADERS = BoxTrapper_getheadersfromfile( $path, $opts );
        $data->{from}    = BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', $rHEADERS ) );
        $data->{subject} = BoxTrapper_getheader( 'subject', $rHEADERS ) || '';
        if ( !$data->{from} ) {
            $data->{error} = locale->maketext('Some headers are missing or corrupt.');
        }
    };
    if ( my $exception = $@ ) {
        $data->{error} = $exception;
        return $data;
    }

    return $data;
}

=head2 _ensure_boxtrapper_dir(DIR, OPTS)

Make sure the directory exists for BoxTrapper for the specific email account that has the passed in directory.

=head3 ARGUMENTS

=over

=item DIR - string

Directory where the emails are stored for this specific email account.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

string - the BoxTrapper directory for the email account.

=cut

sub _ensure_boxtrapper_dir {
    my ( $emaildir, $opts ) = @_;
    my $boxtrapper_dir = "$emaildir/boxtrapper";
    Cpanel::SafeDir::MK::safemkdir( $boxtrapper_dir, 0700 ) unless -d $boxtrapper_dir;
    return $boxtrapper_dir;
}

=head2 _ensure_boxtrapper_search_db(DIR, OPTS)

Make sure the BoxTrapper search database exists for the specific email account.

=head3 ARGUMENTS

=over

=item DIR - string

Directory where the emails are stored for this specific email account.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

string - the path to the BoxTrapper search database for the email account.

=cut

sub _ensure_boxtrapper_search_db {
    my ( $emaildir, $opts ) = @_;
    my $boxtrapper_dir = _ensure_boxtrapper_dir( $emaildir, $opts );
    my $search_db_path = "$boxtrapper_dir/search.db";

    # Create an empty db if it does not exist
    open( my $SDB, '>>', $search_db_path ) or die "Cannot open $search_db_path: $!";
    close($SDB);

    return $search_db_path;
}

# DEPRECATED: Call can be deleted once API1 is deprecated in 86
sub BoxTrapper_showqueue {
    my ( $logdate, $account, $showfile, $bxaction, $skipcontrols ) = @_;

    return if !_role_is_enabled();

    my $blocked = list_queue( $logdate, $account );

    my $esc_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);
    $bxaction = Cpanel::Encoder::Tiny::safe_html_encode_str($bxaction);

    my $showfiledelete = $showfile;
    my $multimsgaction = $showfile;
    if ( $showfile eq 'showmsg.html' ) {
        $showfiledelete = 'msgaction.html';
        $multimsgaction = 'multimsgaction.html';
    }
    $showfiledelete = Cpanel::Encoder::Tiny::safe_html_encode_str($showfiledelete);
    $multimsgaction = Cpanel::Encoder::Tiny::safe_html_encode_str($multimsgaction);

    if ( !$skipcontrols ) {
        print qq{<form name="input" action="$multimsgaction" method="GET">\n};
    }
    print qq{<input type="hidden" name="account" value="$esc_account">\n};
    print qq{<input type="hidden" name="bxaction" value="multimsgaction">\n};
    my $bg;
    my $i = 0;

    use bytes;    # Avoid wide character errors from _safe_mime_header_decode
    foreach my $msg (@$blocked) {
        my $html_queuefile = Cpanel::Encoder::Tiny::safe_html_encode_str( $msg->{'queuefile'} );
        my $html_email     = Cpanel::Encoder::Tiny::safe_html_encode_str( $msg->{'email'} );
        my $html_subject   = Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::StringFunc::SplitBreak::textbreak( _safe_mime_header_decode( $msg->{'subject'} ) ) );

        $bg = ( ++$i % 2 == 0 ? 1 : 2 );
        print <<"EOM";
        <tr class="tdshade${bg}">
            <td width="5%"><input type="checkbox" name="msgid${i}" value="$html_queuefile"></td>
            <td class="truncate" truncate="25" width="15%"><a href="${showfile}?account=${esc_account}&amp;q=$html_queuefile&amp;bxaction=${bxaction}">$html_email</a></td>
            <td style="word-wrap: break-word;"><a href="${showfile}?account=${esc_account}&amp;q=$html_queuefile&amp;bxaction=${bxaction}">$html_subject</a></td>
            <td width="15%"><a href="${showfile}?account=${esc_account}&amp;q=$html_queuefile&amp;bxaction=${bxaction}">$msg->{'nicetime'}</a></td>
        </tr>
EOM
    }
    if ( !$skipcontrols ) {
        my $submit = locale()->maketext('Submit');
        print <<"EOM";
    <tr>
        <td colspan="2">
            <input type="radio" name="multimsg" value="deleteall">Delete</input><br />
            <input type="radio" name="multimsg" value="whitelistall">Whitelist &amp; Deliver</input><br />
            <input type="submit" class="input-button" value="$submit">
        </td>
        <td colspan="3">&nbsp;</td>
    </tr>
    </form>
EOM
    }

    return;
}

# DEPRECATED: Call can be deleted once API1 is deprecated in 86
sub BoxTrapper_showqueuesearch {    ## no critic qw(ProhibitManyArgs  ProhibitExcessComplexity)
    my ( $field, $string, $account, $showfile, $bxaction, $skipcontrols ) = @_;

    return if !_role_is_enabled();

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    if ( !defined $string || $string eq '' ) {
        my $nosrchresults = locale()->maketext('No Search Results');
        my $notavailable  = locale()->maketext('[output,acronym,N/A,Not Applicable]');
        print <<"EOM";
<tr>
    <td>$nosrchresults</td>
    <td>$notavailable</td>
    <td>$notavailable</td>
    <td>$notavailable</td>
</tr>
EOM
        return;
    }

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print locale()->maketext( 'The system failed to locate a home directory for the account “[_1]”.', Cpanel::Encoder::Tiny::safe_html_encode_str($account) ) . "\n";
        return;
    }

    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );

    if ( $emaildir eq '' || $emaildeliverdir eq '' ) {
        print locale()->maketext( 'Email directory for account “[_1]” does not exist.', Cpanel::Encoder::Tiny::safe_html_encode_str($account) ) . "\n";
        return;
    }

    my @BXMSG;
    if ( my $searchregex = eval { qr/$string/im; } ) {
        my @invalid_search_db_entries;
        my ( $qmon, $qmday, $qyear, $qhour, $qmin, $qsec );
        if ( $field eq 'sender' || $field eq 'subject' ) {
            my $searchdir = "$emaildir/boxtrapper";

            Cpanel::SafeDir::MK::safemkdir( $searchdir, 0700 ) unless -d $searchdir;

            open( my $SDB, '>>', "$emaildir/boxtrapper/search.db" ) or die "Cannot open $emaildir/boxtrapper/search.db: $!";
            close($SDB);
            my $sdblock = Cpanel::SafeFile::safeopen( $SDB, '+<', $emaildir . '/boxtrapper/search.db' );
            if ( !$sdblock ) {
                $logger->warn("Could not edit $emaildir/boxtrapper/search.db");
                return;
            }
            my $sdb;
            eval { $sdb = _loadsearchdb($SDB); };
            Cpanel::SafeFile::safeclose( $SDB, $sdblock );

            my $searchkey = 'from';
            if ( $field eq 'subject' ) { $searchkey = 'subject'; }
            my $message_creation_time;
            foreach my $msg (
                grep {
                         ( ref $sdb->{$_}{$searchkey} eq 'ARRAY' )
                      && ( grep { $_ =~ tr/\&// ? ( Cpanel::Encoder::Tiny::safe_html_decode_str($_) =~ m/$searchregex/im ) : m/$searchregex/im } @{ $sdb->{$_}{$searchkey} } )
                }
                keys %{$sdb}
            ) {
                if ( -e $emaildir . '/boxtrapper/queue/' . $msg . '.msg' ) {    # Don't add message that doesn't exist to results
                    $message_creation_time = ( $msg =~ tr/-// ) ? ( split( /\-/, $msg ) )[1] : ( stat(_) )[9];

                    # Retrieve the creation from the filename if possible (otherwise fallback to mtime)   to avoid the problem in case 47038
                    ( $qmon, $qmday, $qyear, $qhour, $qmin, $qsec ) = BoxTrapper_nicedate($message_creation_time);
                    my $rHEADERS = BoxTrapper_getheadersfromfile( $emaildir . '/boxtrapper/queue/' . $msg . '.msg' );
                    push @BXMSG,
                      {
                        'time'      => $message_creation_time,
                        'queuefile' => $msg . '.msg',
                        'email'     => BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', $rHEADERS ) ),
                        'subject'   => BoxTrapper_getheader( 'subject', $rHEADERS ),
                        'nicetime', "$qmon/$qmday ${qhour}:${qmin}:${qsec}"
                      };
                }
                else {
                    push @invalid_search_db_entries, $msg;
                }
            }
        }
        elsif ( $field eq 'body' ) {
            my $dir = $emaildir . '/boxtrapper/queue';
            if ( _opendir_if_exists_or_warn( my $qdir, $dir ) ) {
                while ( my $queuefile = readdir($qdir) ) {
                    next if ( $queuefile =~ /^\./ || $queuefile =~ /\.lock$/ );
                    my $file_to_search = "${emaildir}/boxtrapper/queue/${queuefile}";
                    my ( $bodyref, $mtime ) = _extractbody_scalarref_mtime( $file_to_search, 1024 * 256 );
                    if ( $$bodyref =~ m/$searchregex/im ) {
                        my $rHEADERS = BoxTrapper_getheadersfromfile($file_to_search);
                        ( $qmon, $qmday, $qyear, $qhour, $qmin, $qsec ) = BoxTrapper_nicedate($mtime);
                        push @BXMSG,
                          {
                            'time'      => $mtime,
                            'queuefile' => $queuefile,
                            'email'     => BoxTrapper_extractaddress( BoxTrapper_getheader( 'from', $rHEADERS ) ),
                            'subject'   => BoxTrapper_getheader( 'subject', $rHEADERS ),
                            'nicetime', "$qmon/$qmday ${qhour}:${qmin}:${qsec}"
                          };
                    }
                }
            }
        }

        # Delete invalid entries from search.db
        if (@invalid_search_db_entries) {
            BoxTrapper_removefromsearchdb( $emaildir, \@invalid_search_db_entries );
        }
    }

    my $showfiledelete = $showfile;
    my $multimsgaction = $showfile;
    if ( $showfile eq 'showq.html' ) {
        $showfiledelete = 'showq.html';
        $multimsgaction = 'multimsgaction.html';
        $showfile       = 'showmsg.html';
    }

    if ( !$skipcontrols ) {
        print qq{<form name="input" action="$multimsgaction" method="GET">\n};
    }
    my $html_safe_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);
    print qq{<input type="hidden" name="account" value="$html_safe_account">\n};
    print qq{<input type="hidden" name="bxaction" value="multimsgaction">\n};

    if ( !@BXMSG ) {
        my $nosrchresults = locale()->maketext('No Search Results');
        my $notavailable  = locale()->maketext('[output,acronym,N/A,Not Applicable]');
        print <<"EOM";
<tr>
    <td>$nosrchresults</td>
    <td>$notavailable</td>
    <td>$notavailable</td>
    <td>$notavailable</td>
</tr>
EOM
        return;
    }

    my $i = 0;
    my $bg;
    use bytes;    # Avoid wide character errors from _safe_mime_header_decode
    foreach my $msg ( sort { $a->{'time'} <=> $b->{'time'} } @BXMSG ) {
        if ( !exists $msg->{'email'} || $msg->{'email'} eq '' ) {
            Cpanel::Logger::cplog( "BoxTrapper queued message $msg->{'queuefile'} for user $Cpanel::user invalid", 'info', __PACKAGE__, 1 );
            next;
        }
        my $new_subject = Cpanel::StringFunc::SplitBreak::textbreak( _safe_mime_header_decode( $msg->{'subject'} ) );
        $bg = ( ++$i % 2 == 0 ? 1 : 2 );

        my $html_safe_queuefile   = Cpanel::Encoder::Tiny::safe_html_encode_str( $msg->{'queuefile'} );
        my $html_safe_email       = Cpanel::Encoder::Tiny::safe_html_encode_str( $msg->{'email'} );
        my $html_safe_nicetime    = Cpanel::Encoder::Tiny::safe_html_encode_str( $msg->{'nicetime'} );
        my $html_safe_new_subject = Cpanel::Encoder::Tiny::safe_html_encode_str($new_subject);

        my $showfile_qs = Cpanel::HTTP::QueryString::make_query_string( { 'account' => $account, 'q' => $msg->{'queuefile'}, 'bxaction' => $bxaction } );
        print <<"EOM";
        <tr class="tdshade${bg}">
            <td width="5%"><input type="checkbox" name="msgid${i}" value="$html_safe_queuefile"></td>
            <td class="truncate" truncate="25" width="15%"><a href="${showfile}?${showfile_qs}">$html_safe_email</a></td>
            <td style="word-wrap: break-word;"><a href="${showfile}?${showfile_qs}">$html_safe_new_subject</a></td>
            <td width=\"15%\"><a href="${showfile}?${showfile_qs}\">$html_safe_nicetime</a></td>
        </tr>
EOM
    }
    if ( !$skipcontrols ) {
        my $submit = locale()->maketext('Submit');
        print <<"EOM";
    <tr>
        <td colspan="2">
            <input type="radio" name="multimsg" value="deleteall">Delete</input>
            <br />
            <input type="radio" name="multimsg" value="whitelistall">Whitelist & Deliver</input><br />
            <input type="submit" class="input-button" value="$submit">
        </td>
        <td colspan="3">&nbsp</td>
    </tr>
    </form>
EOM
    }

    return;
}

sub _opendir_if_exists_or_warn {
    my $ok = opendir $_[0], $_[1];

    if ( !$ok && $! != _ENOENT() ) {
        Cpanel::Logger::cplog( "Failed to open BoxTrapper directory “$_[1]”: $!", 'warn', __PACKAGE__, 1 );
    }

    return $ok;
}

sub BoxTrapper_showmin_spam_score_deliver {
    my (@args) = @_;

    return if !_role_is_enabled();

    my $conf = _get_conf_by_acct(@args);

    if ( !exists $conf->{'min_spam_score_deliver'} || !defined $conf->{'min_spam_score_deliver'} ) {
        print "-2.5";
    }
    else {
        print( $conf->{'min_spam_score_deliver'} / 10 );
    }

    return;
}

sub BoxTrapper_showwhitelist_by_assoc {
    my (@args) = @_;

    return if !_role_is_enabled();

    my $conf = _get_conf_by_acct(@args);

    if ( $conf->{'whitelist_by_assoc'} ) {
        $Cpanel::CPVAR{'showwhitelist_by_assoc_checked'} = 1;
        print 'checked="checked"';
    }
    else {
        $Cpanel::CPVAR{'showwhitelist_by_assoc_checked'} = 0;
    }

    return;
}

sub BoxTrapper_showfromname {
    my (@args) = @_;

    return if !_role_is_enabled();

    my $conf = _get_conf_by_acct(@args);

    print Cpanel::Encoder::Tiny::safe_html_encode_str( $conf->{'fromname'} );

    return;
}

sub BoxTrapper_showqueuetime {
    my (@args) = @_;

    return if !_role_is_enabled();

    my $conf = _get_conf_by_acct(@args);

    print Cpanel::Encoder::Tiny::safe_html_encode_str( $conf->{'stale-queue-time'} );

    return;
}

sub _get_conf_by_acct {
    my $account     = shift;
    my $esc_account = Cpanel::Encoder::Tiny::safe_html_encode_str($account);
    my $locale      = Cpanel::Locale->get_handle();
    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo($account);
    if ( !$homedir ) {
        print $locale->maketext( 'The system failed to locate a home directory for the account “[_1]”.', $esc_account ) . "\n";
        return;
    }

    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs( $account, $homedir );
    if ( $emaildir eq "" || $emaildeliverdir eq "" ) {
        print $locale->maketext( 'Email directory for account “[_1]” does not exist.', $esc_account ) . "\n";
        return;
    }
    my $conf = BoxTrapper_loadconf( $emaildir, $account );
    return $conf;
}

sub BoxTrapper_status {
    my $account = shift;

    return if !_role_is_enabled();

    return if !Cpanel::hasfeature('boxtrapper');
    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my $enabled = BoxTrapper_isenabled($account);
    my $status;
    if ($enabled) {
        $status = "<font class=\"redtext\">" . $locale->maketext('Enabled') . "</font>\n";
    }
    else {
        $status = "<font class=\"blacktext\">" . $locale->maketext('Disabled') . "</font>\n";
    }
    print $status;

    return;
}

sub BoxTrapper_statusbutton {
    my $account = shift;

    return if !_role_is_enabled();

    return if !Cpanel::hasfeature('boxtrapper');
    my $locale = Cpanel::Locale->get_handle();

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }
    my $enabled = BoxTrapper_isenabled($account);
    if ($enabled) {
        print "<input type=\"hidden\" name=\"action\" value=\"Disable\">\n";
        print "<input type=\"submit\" class=\"input-button\" name=\"submitaction\" value=\"" . $locale->maketext('Disable') . "\">\n";
    }
    else {
        print "<input type=\"hidden\" name=\"action\" value=\"Enable\">\n";
        print "<input type=\"submit\" class=\"input-button\" name=\"submitaction\" value=\"" . $locale->maketext('Enable') . "\">\n";
    }

    return;
}

sub BoxTrapper_getboxconfdir {
    my ( $account, $ret, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    return if !_role_is_enabled();

    my $locale = Cpanel::Locale->get_handle();
    $account = _get_account($account);

    my ( $homedir, $domain ) = BoxTrapper_getaccountinfo( $account, undef, $opts );
    if ( !$homedir ) {
        _handle_error(
            locale()->maketext( 'The system failed to locate the home directory for the email account, [_1].', $account ),
            $opts,
        );
        return;
    }

    my ( $emaildir, $emaildeliverdir ) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        $Cpanel::BoxTrapper::CORE::SKIP_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::SKIP_CREATE_EMAIL_DIRS,
        $opts
    );
    if ( $emaildir eq '' || $emaildeliverdir eq '' ) {
        _handle_error(
            locale()->maketext( 'The system experienced issues when it tried to access the email account, [_1].', $account ),
            $opts,
        );
        return;
    }

    if ( !-e $emaildir . '/.boxtrapper' ) {
        Cpanel::SafeDir::MK::safemkdir( $emaildir . '/.boxtrapper', 0700 );
    }

    if ($ret) {
        return $emaildir . '/.boxtrapper';
    }

    print Cpanel::Encoder::Tiny::safe_html_encode_str( $emaildir . '/.boxtrapper' ) if ( $opts->{api1} );
    return;
}

# This function is used to print directly into the query parameter portion of HREF tags
# There is no proper way to print errors in this context, so the existing behavior of printing HTML
# on errors is preserved.
sub BoxTrapper_getboxconfdiruri {
    my $account = shift;
    my $ret     = shift;

    return if !_role_is_enabled();

    my $result = BoxTrapper_getboxconfdir( $account, 1 );
    if ( !defined $result ) {
        return;
    }
    elsif ($ret) {
        return Cpanel::Encoder::URI::uri_encode_str($result);
    }
    print Cpanel::Encoder::URI::uri_encode_str($result);

    return;
}

=head2 get_forwarders(EMAIL, CONFIG)

Gets the raw forwarder data from the configuration file parsed into lines.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email account to add the forwarders to.

=item CONFIG - hashref

With the following properties:

=over

=item uapi - Boolean

When 1 use UAPI semantics, otherwise, use API 1 semantics.

=back

=back

=head3 RETURNS

Arrayref of strings - the lines from the forward-list.txt for the email account.

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the config file cannot be read.

=back

=cut

sub get_forwarders {
    my ( $email, $opts ) = @_;
    return BoxTrapper_fetchcfgfile( $email, 'list', 'forward-list.txt', $opts );
}

=head2 set_forwarders(EMAIL, FORWARDERS, CONFIG)

=head3 ARGUMENTS

=over

=item EMAIL - string

The email account to add the forwarders to.

=item FORWARDERS - arrayref of string

List of forwarder lines to replace the file with.

=item CONFIG - hashref

With the following properties:

=over

=item uapi - Boolean

When 1 use UAPI semantics, otherwise, use API 1 semantics.

=item verification - Boolean

When 1, perform verifications. Otherwise do not.

=back

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the config file cannot be written.

=back

=cut

sub save_forwarders {
    my ( $account, $forwarders, $opts ) = @_;

    my $page = '';
    $page = join( "\n", @$forwarders ) if @$forwarders;

    if ( BoxTrapper_savecfgfile( $account, 'list', 'forward-list.txt', $page, $opts ) ) {
        return BoxTrapper_cleancfgfilelist( $account, 'list', 'forward-list.txt', $opts );
    }
    return 0;
}

=head2 get_blocklist(EMAIL, OPTS)

Gets the blocklist.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address for which to get the blocklist

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

Arrayref of strings - the lines from the black-list.txt for the email account.

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the blocklist file cannot be read.

=back

=cut

sub get_blocklist {
    my ( $email, $opts ) = @_;

    return BoxTrapper_fetchcfgfile( $email, 'list', 'black-list.txt', $opts );
}

=head2 set_blocklist(EMAIL, RULES, OPTS)

Sets the blocklist.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address for which to set the blocklist

=item RULES - arrayref of string

List of blocking regular expression lines to replace the blocklist file with.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the blocklist file cannot be read.

=back

=cut

sub set_blocklist {
    my ( $email, $rules, $opts ) = @_;

    my $page = '';
    $page = join( "\n", @$rules ) if @$rules;

    if ( BoxTrapper_savecfgfile( $email, 'list', 'black-list.txt', $page, $opts ) ) {
        return BoxTrapper_cleancfgfilelist( $email, 'list', 'black-list.txt', $opts );
    }
    return 0;
}

=head2 get_allowlist(EMAIL, OPTS)

Gets the allowlist.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address for which to get the allowlist

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

Arrayref of strings - the lines from the allowlist for the email account.

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the allowlist file cannot be read.

=back

=cut

sub get_allowlist {
    my ( $email, $opts ) = @_;

    return BoxTrapper_fetchcfgfile( $email, 'list', 'white-list.txt', $opts );
}

=head2 set_allowlist(EMAIL, RULES, OPTS)

Sets the allowlist.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address for which to set the allowlist.

=item RULES - arrayref of string

List of blocking regular expression lines to replace the allowlist file with.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the allowlist file cannot be read.

=back

=cut

sub set_allowlist {
    my ( $email, $rules, $opts ) = @_;

    my $page = '';
    $page = join( "\n", @$rules ) if @$rules;

    if ( BoxTrapper_savecfgfile( $email, 'list', 'white-list.txt', $page, $opts ) ) {
        return BoxTrapper_cleancfgfilelist( $email, 'list', 'white-list.txt', $opts );
    }
    return 0;
}

=head2 get_ignorelist(EMAIL, OPTS)

Gets the ignorelist.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email account that uses the ignorelist.

=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

Arrayref of strings - the lines from the ignorelist for the email account.

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the ignorelist file cannot be read.

=back

=cut

sub get_ignorelist {
    my ( $email, $opts ) = @_;

    return BoxTrapper_fetchcfgfile( $email, 'list', 'ignore-list.txt', $opts );
}

=head2 set_ignorelist(EMAIL, RULES, OPTS)

Sets the ignorelist.

=head3 ARGUMENTS

=over

=item EMAIL - string

The email address for which to set the ignorelist.

=item RULES - arrayref of string

List of blocking regular expression lines to replace the ignorelist file with.


=item OPTS - hash

Configuration options for the call. See C<list_queue> above for details.

=back

=head3 RETURNS

N/A

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=item When the ignorelist file cannot be read.

=back

=cut

sub set_ignorelist {
    my ( $email, $rules, $opts ) = @_;

    my $page = '';
    $page = join( "\n", @$rules ) if @$rules;

    if ( BoxTrapper_savecfgfile( $email, 'list', 'ignore-list.txt', $page, $opts ) ) {
        return BoxTrapper_cleancfgfilelist( $email, 'list', 'ignore-list.txt', $opts );
    }
    return 0;
}

=head2 BoxTrapper_savecfgfile(ACCOUNT, TYPE, FILE, PAGE, OPTS)

Save a configuration file.

=cut

sub BoxTrapper_savecfgfile {
    my ( $account, $filetype, $cfgfile, $page, $opts ) = @_;

    _assert_feature_enabled();

    $cfgfile =~ s/\///g;
    $cfgfile =~ s/\.\.//g;

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my $email_dir = BoxTrapper_getboxconfdir( $account, 1, $opts );

    my $file;
    if ( $filetype eq 'list' ) {
        $file = $email_dir . '/' . $cfgfile;
    }
    elsif ( $filetype eq 'msg' ) {
        $file = $email_dir . '/forms/' . $cfgfile;
    }

    # Need to decode page
    if ( my $lock = Cpanel::SafeFile::safeopen( my $write_fh, '>', $file ) ) {

        # Remove any loose <CR>
        $page =~ s/\r//g;

        print {$write_fh} HTML::Entities::decode_entities($page);

        Cpanel::SafeFile::safeclose( $write_fh, $lock );
    }
    else {
        my $error = $!;
        Cpanel::Logger::cplog( "Failed to write $file: $error", 'warn', __PACKAGE__, 1 );

        if ( $opts->{uapi} ) {
            die Cpanel::Exception::create(
                "IO::FileWriteError",
                "The system failed to save the “[_1]” configuration file: “[output,asis,_2]”.",
                [ $file, $error ]
            );
        }
    }

    return 1 if $opts->{uapi};
    return;
}

=head2 BoxTrapper_cleancfgfilelist(ACCOUNT, TYPE, FILE, OPTS)

Clean up the configuration file contents.

=cut

sub BoxTrapper_cleancfgfilelist {
    my ( $account, $filetype, $cfgfile, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    _assert_feature_enabled();

    $cfgfile =~ s/\///g;
    $cfgfile =~ s/\.\.//g;

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my $file;
    if ( $filetype eq 'list' ) {
        $file = BoxTrapper_getboxconfdir( $account, 1, $opts ) . '/' . $cfgfile;
    }
    else {
        return;
    }

    return BoxTrapper_cleanlist( $file, $opts );
}

=head2 BoxTrapper_fetchcfgfile(ACCOUNT, TYPE, FILE, OPTS)

Fetch the contents of the specific configuration file.

=cut

sub BoxTrapper_fetchcfgfile {
    my ( $account, $filetype, $cfgfile, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    return if !_role_is_enabled();
    return if !Cpanel::hasfeature('boxtrapper');

    $cfgfile =~ s/\///g;
    $cfgfile =~ s/\.\.//g;

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    my $file;
    if ( $filetype eq 'list' ) {
        $file = BoxTrapper_getboxconfdir( $account, 1, $opts ) . '/' . $cfgfile;
    }
    elsif ( $filetype eq 'msg' ) {
        $file = BoxTrapper_getboxconfdir( $account, 1, $opts ) . '/forms/' . $cfgfile;
    }

    return [] if !-e $file;

    my @list;
    if ( open my $read_fh, '<', $file ) {
        while ( my $line = readline $read_fh ) {

            # Check for bug where encoded strings would be saved
            if ( $line =~ m/\&\#\d{2}\;/ ) {
                $line = HTML::Entities::decode_entities($line);
            }

            if ( $opts->{api1} ) {
                print Cpanel::Encoder::Tiny::safe_html_encode_str($line);
            }
            else {
                $line =~ s/(^[\s\n]*)|([\s\n]*$)//;
                push @list, $line;
            }
        }
        close $read_fh;
    }
    else {
        my $exception = $!;
        if ( $opts->{uapi} ) {
            die Cpanel::Exception::create( 'IO::FileReadError', [ path => $file, error => $exception ] );
        }
        else {
            Cpanel::Logger::cplog( "Failed to read $file: $exception", 'warn', __PACKAGE__, 1 );
        }
    }

    if ( $opts->{uapi} ) {

        # The current contents of @list is an array of strings with newline characters.
        # This behavior is not desired in UAPI, so we use chomp() to strip these excess newlines.
        chomp(@list);

        # For lists of rules, forwarders, etc. ($filetype eq 'list') returned by UAPI, empty lines
        # are not helpful, so we use an additional grep to ensure these are stripped. They are
        # generally desired for message templates ($filetype eq 'msg') but not when the template
        # only contains empty lines. In that scenario, we will return an empty array.
        my @lines_with_content = grep { $_ } @list;
        @list = @lines_with_content if $filetype eq 'list' || !@lines_with_content;

        return \@list;
    }
    return;
}

=head2 BoxTrapper_isenabled(ACCOUNT, ACTION, OPTS)

Check if BoxTrapper is enabled or disabled for an ACCOUNT.

=head3 NOTES

This is the API 1 implementation and is used internally
by the UAPI call Cpanel::API::BoxTrapper::get_status

=head3 ARGUMENTS

=over

=item ACCOUNT - string

Either a cpanel user name or an email account.

=item OPTS - hashref

=over

=item api1 - Boolean

Provides error handing and output using API 1 semantics. (print, Cpanel::CPERROR)

=item uapi - Boolean

Provide error handling by throwing exceptions

=item validate - Boolean

Enabled ownership and existence validation for the email account. Defaults to not performing the validation.

=back

=back

=head3 RETURNS

1 if BoxTrapper is enabled, 0 if BoxTrapper is disabled

When in 'api1' mode, it will return undef on any error.

When in 'uapi' mode, all error are thrown as exceptions.

=head3 SIDE EFFECTS

Note that in 'api1' mode there are several possible side effects:

=over

=item There may be prints to STDOUT

=item There may be values set to $Cpanel::CPERROR{'boxtrapper'}

=back

=cut

sub BoxTrapper_isenabled {
    my ( $account, $opts ) = @_;
    $opts = { api1 => 1 } if !$opts;

    return if !_role_is_enabled();

    if ( $Cpanel::appname eq 'webmail' ) {
        $account = $Cpanel::authuser;
    }

    if ( !$account ) {
        Cpanel::Logger::cplog( 'Missing argument', 'warn', __PACKAGE__, 1 );
        _handle_error(
            locale()->maketext('Failed to retrieve the status of [asis,BoxTrapper].'),
            $opts,
        );
        return;
    }
    my ($homedir) = BoxTrapper_getaccountinfo( $account, undef, $opts );
    if ( !$homedir ) {
        _handle_error(
            locale()->maketext( 'The system failed to locate the home directory for the email account, [_1].', $account ),
            $opts,
        );
        return;
    }

    my ($emaildir) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        $Cpanel::BoxTrapper::CORE::SKIP_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::SKIP_CREATE_EMAIL_DIRS,
        $opts
    );
    if ( !$emaildir ) {
        _handle_error(
            locale()->maketext( 'The system experienced issues when it tried to access the email account, [_1].', $account ),
            $opts,
        );
        return;
    }
    return -e $emaildir . '/.boxtrapperenable' ? 1 : 0;
}

sub BoxTrapper_logdate {
    my $logdate = shift;

    return if !_role_is_enabled();

    if ( $logdate eq '' ) { $logdate = time(); }
    my ( $mon, $mday, $year ) = BoxTrapper_nicedate($logdate);
    print $mon . '-' . $mday . '-' . $year;

    return;
}

sub _loadsearchdb {
    my ( $fh, $encode ) = @_;
    my ( $search_database, $inname, $name, $key, $startpos );
    while ( my $rline = readline($fh) ) {
        $inname = $name = '';
        while ( $rline =~ m/(\<[^\>\<]+\>*)/g ) {
            $startpos = ( pos($rline) - length($1) );
            if ($inname) {
                $name   = substr( $rline, 0, $startpos );
                $inname = '';
            }
            elsif ( $startpos > 0 && $name ne '' ) {
                push( @{ $search_database->{$name}->{$key} }, ( $encode ? Cpanel::Encoder::Tiny::safe_html_decode_str( substr( $rline, 0, $startpos ) ) : substr( $rline, 0, $startpos ) ) );
            }
            $inname = 1 if ( $1 !~ tr/\/// && ( ( $key = $1 ) =~ tr/\<\>//d ) && $key eq 'id' );
            substr( $rline, 0, pos($rline), '' );
        }
    }
    return $search_database;
}

#
# _extractbody_scalarref_mtime will open the file, save the mtime then read the first 8192 bytes and check to see if it is the headers
# and then use it and advance the file handle to read the body
# if it does not find the headers in the first 8192 bytes it will advance to 8192-5 bytes and start looking for
# the termination of the headers then advanced the file handle to read the body
#
sub _extractbody_scalarref_mtime {
    my ( $filename, $limit ) = @_;
    return if !$filename;
    my $buffer_size = 8192;
    my ( $body, $mtime );
    if ( open my $msg_fh, '<', $filename ) {
        $mtime = ( stat($msg_fh) )[9];
        read( $msg_fh, $body, $buffer_size );
        if ( $body =~ m/\r?\n\r?\n/g && $+[0] ) {
            seek( $msg_fh, $+[0], 0 );
        }
        else {
            seek( $msg_fh, $buffer_size - 5, 0 );
            while ( readline($msg_fh) ) {
                last if (m/$Cpanel::Regex::regex{'emailheaderterminator'}/);
            }
        }
        if ($limit) {
            read( $msg_fh, $body, $limit );
        }
        else {
            local $/;
            $body = readline($msg_fh);
        }
        close($msg_fh);
    }
    return ( \$body, $mtime );
}

sub _safe_mime_header_decode {
    my $header = shift;

    return '' if !length $header;    # may have an empty subject

    my $decoded_header = eval { Cpanel::CPAN::Encode::MIME::Header::decode($header) };

    #Do NOT use encode('UTF-8', ...) in compiled code. (cf. FB 137797)
    utf8::encode($decoded_header) if $decoded_header;
    return $decoded_header ? $decoded_header : $header;
}

=head2 save_configuration(EMAIL, CONFIG)

Save the BoxTrapper configuration properties for the given mailbox.

=head3 ARGUMENTS

=over

=item EMAIL - string

Account the configuration is for.

=item CONFIG - hashref

With the following properties:

=over

=item from_addresses - string

Comma-separated list of email address to use in the from field for messages sent to the senders of blocked or ignored messages.

=item from_name - string

The personal name that the system uses in emails that it sends to blocked or ignored senders

=item queue_days - integer

The number of days that you wish to keep logs and messages in the queue.

=item spam_score - number

Minimum Apache SpamAssassin Spam Score required to bypass BoxTrapper

=item enable_auto_whitelist - Boolean

When 1, when emails are sent from the email account, recipients in the To: and CC: fields are auto-whitelisted. When set to 0, no auto-whitelisting occurs.

=item whitelist_by_association - Boolean

Automatically whitelist the To and From lines from whitelisted senders

=back

=back

=head3 RETURNS

1 when it succeeds. Failures are reported with exceptions.

=head3 THROWS

=over

=item When the 'boxtrapper' feature is disabled

=item When the 'MailReceive' role is not available on the server.

=item When the account is in DEMO more.

=item When the CONFIG parameter is not a hash reference.

=item WHen one of the required parameters is missing.

=item When one of the following is not a boolean value: enable_auto_whitelist, whitelist_assoc

=item When 'from_addresses' property is not a comma delimited list of valid cPanel email addresses or exceeds the length of 2560 or has more than 10 email addresses in it.

=item When 'queue_days' is not a positive integer

=item When 'spam_score' is not a number.

=item When 'from_name' is longer than 128 characters or contains no ASCII characters.

=item When the requested email account is not owned by the cPanel user

=item When the requested email account does not exist.

=item When the various BoxTrapper configuration storage files cannot be opened, written to or deleted.

=back

=cut

sub save_configuration {
    my ( $account, $params ) = @_;

    _assert_feature_enabled();
    if ( ref $params ne 'HASH' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The [asis, params] must be a hash for [asis, save_configuration].' );
    }

    for my $required (qw(from_addresses queue_days enable_auto_whitelist whitelist_assoc)) {
        if ( !exists( $params->{$required} ) || !defined( $params->{$required} ) ) {
            die Cpanel::Exception::create(
                'InvalidParameter',
                'The “[_1]” argument is required.',
                [$required],
            );
        }
    }

    # Fill in the missing optional parameters with the values already stored
    if ( !exists( $params->{spam_score} ) || !exists $params->{from_name} ) {

        my $config = get_configuration($account);

        if ($config) {
            $params->{spam_score} = $config->{min_spam_score_deliver} if exists $config->{min_spam_score_deliver} && !exists $params->{spam_score};
            $params->{from_name}  = $config->{fromname}               if exists $config->{fromname}               && !exists $params->{from_name};
        }
    }

    # Validate what we are about to save
    Cpanel::Validate::Boolean::validate_or_die( $params->{'enable_auto_whitelist'} );
    Cpanel::Validate::Boolean::validate_or_die( $params->{'whitelist_assoc'} );
    $params->{'from_addresses'} = _validate_email_csv( $params->{'from_addresses'} );
    $params->{'queue_days'}     = _validate_queue_days( $params->{'queue_days'} );
    $params->{'spam_score'}     = _validate_spam_score( $params->{'spam_score'} );
    $params->{'from_name'}      = _validate_from_name( $params->{'from_name'} );

    $account = _get_account($account);
    my ( $homedir, $emaildir ) = _list_account_directories($account);

    if ( my $lock = Cpanel::SafeFile::safeopen( my $fh, '>', "${emaildir}/boxtrapper.conf" ) ) {

        my $contents = sprintf( "froms=%s\n", $params->{'from_addresses'} );
        $contents .= sprintf( "stale-queue-time=%d\n",       $params->{'queue_days'} );
        $contents .= sprintf( "fromname=%s\n",               $params->{'from_name'} );
        $contents .= sprintf( "min_spam_score_deliver=%d\n", $params->{'spam_score'} );
        $contents .= sprintf( "whitelist_by_assoc=%d\n",     $params->{'whitelist_assoc'} );

        Cpanel::SafeFile::Replace::safe_replace_content( $fh, $lock, $contents );
        Cpanel::SafeFile::safeclose( $fh, $lock );

    }
    else {
        die Cpanel::Exception::create(
            'IO::FileOpenError',
            'The system could not save settings because the system failed open the [asis,BoxTrapper] configuration file.',
        );
    }

    my $auto_whitelist_file = "${emaildir}/.boxtrapperautowhitelistdisable";
    if ( $params->{'enable_auto_whitelist'} ) {
        Cpanel::Autodie::unlink_if_exists($auto_whitelist_file);
    }
    else {
        Cpanel::Autodie::open( my $fhh, '>', $auto_whitelist_file );
        close($fhh);
    }

    return 1;

}

=head2 save_email_template($account, $template, $contents)

Save a BoxTrapper message template for an account.

=head3 ARGUMENTS

=over

=item account - string

Account the template is for.

=item template - string

One of:

=over

=item * blacklist

=item * returnverify

=item * verifyreleased

=item * verify

=back

=item contents - UTF8 string

The contents of the template

=back


=head3 RETURNS

Returns 1 when saving the template is successful.

=head3 THROWS

=over

=item When the requested email account is not owned by the cPanel user

=item When the requested email account does not exist.

=item When the template file cannot be opened or read from.

=item When the template specified is invalid

=item When the size of the template is not between 1 and 4096 bytes

=back

=cut

sub save_email_template {
    my ( $account, $template, $contents ) = @_;

    _assert_feature_enabled();
    _validate_template( $template, $contents );

    $account = _get_account($account);
    my ( $homedir, $emaildir ) = _list_account_directories($account);
    my $path = "${emaildir}/.boxtrapper/forms/${template}.txt";

    if ( my $lock = Cpanel::SafeFile::safeopen( my $fh, '>', $path ) ) {

        Cpanel::SafeFile::Replace::safe_replace_content( $fh, $lock, HTML::Entities::decode_entities($contents) );
        Cpanel::SafeFile::safeclose( $fh, $lock );

    }
    else {
        die Cpanel::Exception::create(
            'IO::FileOpenError',
            'The system could not save settings because the system failed open the “[_1]” template file.',
            [$template]
        );
    }

    return 1;
}

=head2 get_configuration(EMAIL)

Gets the BoxTrapper configuration properties for the given mailbox.

=head3 ARGUMENTS

=over

=item EMAIL - string

Account the configuration is for.

=back

=head3 RETURNS

=over

=item from_addresses - string

Comma-separated list of email address to use in the from field for messages sent to the senders of blocked or ignored messages.

=item from_name - string

The personal name that the system uses in emails that it sends to blocked or ignored senders

=item queue_days - integer

The number of days that you wish to keep logs and messages in the queue.

=item spam_score - number

Minimum Apache SpamAssassin Spam Score required to bypass BoxTrapper

=item enable_auto_whitelist - Boolean

When 1, when emails are sent from the email account, recipients in the To: and CC: fields are auto-whitelisted. When set to 0, no auto-whitelisting occurs.

=item whitelist_by_association - Boolean

Automatically whitelist the To and From lines from whitelisted senders

=back

=head3 THROWS

=over

=item When the requested email account is not owned by the cPanel user

=item When the requested email account does not exist.

=item When the various BoxTrapper configuration storage files cannot be opened or read from.

=back

=cut

sub get_configuration {
    my ($account) = @_;

    _assert_feature_enabled( { 'allow_demo' => 1 } );

    $account = _get_account($account);
    my ( $homedir, $emaildir ) = _list_account_directories($account);
    my $conf = BoxTrapper_loadconf( $emaildir, $account );

    if ( !exists $conf->{'min_spam_score_deliver'} || !defined $conf->{'min_spam_score_deliver'} ) {
        $conf->{'min_spam_score_deliver'} = -2.5;
    }
    else {
        $conf->{'min_spam_score_deliver'} /= 10;
    }

    #this is the only value not returned from CORE::BoxTrapper_loadconf for performance of CORE
    $conf->{'auto_whitelist'} = _is_auto_whitelist_disabled($emaildir);

    return $conf;

}

=head2 reset_email_template($account, $template)

Reset a BoxTrapper message template to the default.

=head3 ARGUMENTS

=over

=item account - string

Account the template is for.

=item template - string

One of:

=over

=item * blacklist

=item * returnverify

=item * verifyreleased

=item * verify

=back

=back


=head3 RETURNS

Returns 1 when resetting the template is successful.

=head3 THROWS

=over

=item When the requested email account is not owned by the cPanel user

=item When the requested email account does not exist.

=item When the default template file cannot be opened or read from.

=item When the template file cannot be overwritten.

=item When the template specified is invalid

=item When the size of the template is not between 1 and 4096 bytes

=back

=cut

sub reset_email_template {
    my ( $account, $template ) = @_;

    _assert_feature_enabled();
    _validate_template($template);

    $account = _get_account($account);
    my ( $homedir, $emaildir ) = _list_account_directories($account);
    my $src  = DEFAULT_TEMPLATE_PATH . "/${template}.txt";
    my $dest = "${emaildir}/.boxtrapper/forms/${template}.txt";

    return _copy_file( $src, $dest );

}

=head2 _copy_file($src, $dest)

Copy $src to $dest. Used here for both resetting default templates and copying if the
requested template doesn't exist yet in the users space.

=head3 ARGUMENTS

=over

=item src - string

The file path to copy

=item dest - string

The destination path to copy to.

=back


=head3 RETURNS

Returns 1 when saving the template is successful.
Value is from return of L<Cpanel::FileUtils::Copy::safecopy>

Note since Cpanel::FileUtils::Copy::safecopy currently prints
to STDERR for some errors, this method will too currently.

=head3 THROWS

=over

=item When Cpanel::FileUtils::Copy::safecopy populates an exception in $@

=back

=cut

sub _copy_file {

    my ( $src, $dest ) = @_;

    require Cpanel::FileUtils::Copy;

    # DUCK-597 todo: safecopy prints data to stderr via log warn.
    # if our usage of Capture::Tiny in LogManager gets merged we can use that here
    # otherwise we have to accept it?
    my $result = eval { Cpanel::FileUtils::Copy::safecopy( $src, $dest ) };
    if ( my $err = $@ ) {
        die Cpanel::Exception->create_raw( $err->to_string_no_id() ) if $err->isa('Cpanel::Exception');
        die Cpanel::Exception->create_raw($err);
    }

    return $result;

}

=head2 _validate_template($template, $contents)

Validate the template name and if provided, the contents.

=head3 ARGUMENTS

=over

=item template - string

One of:

=over

=item * blacklist

=item * returnverify

=item * verifyreleased

=item * verify

=back

=item contents - string - optional

The template contents string.

=back


=head3 RETURNS

Returns 1 when saving the validation is successful. Throws otherwise.

=head3 THROWS

=over

=item When the template is not one of the supported strings.

=item When the content is provided, but not between 1 and 4096 bytes.

=item When the content is provided for the verify template, but the contents do not contain the required msgid string.

=item When the content is provided for the template, but the contents do not contain the required To: %email% string.

=back

=cut

sub _validate_template {
    my ( $template, $contents ) = @_;

    if ( !grep { $template eq $_ } DEFAULT_TEMPLATES ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The template parameter is not valid. It should be one of [list_or_quoted,_1].',
            [ [DEFAULT_TEMPLATES] ]
        );
    }

    if ( defined($contents) ) {

        my $size = length($contents);
        if ( $size > MAX_TEMPLATE_SIZE ) {
            die Cpanel::Exception::create(
                'InvalidParameter',
                'The template content has exceeded the maximum of [format_bytes,_1]. It is currently [format_bytes,_2].',
                [ MAX_TEMPLATE_SIZE, $size ]
            );
        }
        elsif ( $size == 0 ) {    # not that 1 would be useful, anyone suggest a min?
            die Cpanel::Exception::create(
                'InvalidParameter',
                'The template content cannot be empty.'
            );
        }

        if ( $contents !~ m/To: %email%/ ) {
            die Cpanel::Exception::create(
                'InvalidParameter',
                'The template content must contain [asis,To: %email%].'
            );
        }

        if ( $template eq 'verify' && $contents !~ m/Subject:.*verify#%msgid%/ ) {
            die Cpanel::Exception::create(
                'InvalidParameter',
                'The template content must contain [asis,Subject: verify#%msgid%].'
            );
        }

    }

    return 1;
}

=head2 _validate_from_name(FROM) [PRIVATE]

Validates the 'from_name' property. Also removes any leading or trailing whitespace.

=head3 ARGUMENTS

=over

=item FROM - string

=back

=head3 RETURNS

string - from_name with leading and trailing whitespace removed.

=head3 THROWS

=over

=item When the FROM parameter has non-ASCII characters.

=item When the length of the FROM parameter is > 128 characters.

=back

=head3 NOTES

This field does not support UTF-8 Unicode characters at this time. We need to support UTF-8 mail headers and body - partial support exists in Cpanel/BoxTrapper/CORE.pm for subject header already.

=over

=item * https://tools.ietf.org/html/rfc2047

=item * https://tools.ietf.org/html/rfc2045

=back

=cut

sub _validate_from_name {
    my ($from) = @_;

    $from = '' if !defined($from);

    # TODO: CPANEL-27481 - add utf-8 support to BoxTrapper responses.
    $from =~ s/^\s+|\s+$//g;
    if ( $from =~ m/[^A-Za-z0-9\ \-\.\']/ || length($from) > 128 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The name parameter is not valid.' );
    }

    return $from;
}

=head2 _validate_email_csv(ADDRESSES) [PRIVATE]

Validate the from email addresses used to send message back to the senders of blocked emails.

=head3 ARGUMENTS

=over

=item ADDRESSES - string

Single address, comma-delimited list of email addresses, or cpanel user. Also strips leading and trailing whitespace.

=back

=head3 RETURNS

string - Validated addresses. Multiple Comma-delimited addresses are returned as the csv list of email addresses

=head3 THROWS

=over

=item When the total line length is > 2560

=item When there are more then 10 email addresses in the list.

=item When any of the email addresses are invalid cPanel mail addresses.

=back

=cut

sub _validate_email_csv {
    my ($addresses) = @_;

    $addresses =~ s/\s//g;

    #support just for default cpanel username
    return $addresses if ( defined($Cpanel::user) && ( $addresses eq $Cpanel::user ) );

    my @addresses = split( /\s*,\s*/, $addresses );

    if ( length($addresses) > 2560 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The maximum number of characters for the [asis,from] email address list is “[_1]”.', [2560] );
    }

    if ( scalar @addresses > 10 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The maximum number of email addresses in the [asis,from] email address list is “[_1]”.', [10] );
    }

    my @invalid_addresses = grep { !Cpanel::Validate::EmailCpanel::is_valid($_) } @addresses;
    if (@invalid_addresses) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,from] email address list contains one or more invalid email addresses: [_1]', [ join( ', ', @invalid_addresses ) ] );
    }

    return $addresses;
}

=head2 _validate_queue_days(DAYS) [PRIVATE]

Validates that the DAYS parameter is a positive integer. Also trims out any whitespace.

=head3 ARGUMENTS

=over

=item DAYS - string

=back

=head3 RETURNS

integer - number of days

=head3 THROWS

=over

=item When the 'DAYS' is not a positive integrer.

=back

=cut

sub _validate_queue_days {
    my ($days) = @_;

    $days =~ s/\s//g;
    if ( $days !~ /^[1-9][0-9]*$/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Number of days to keep logs must be a positive integer.' );
    }

    if ( $days > ( ~0 >> 1 ) ) {    # days > MAX_INT
        die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a positive integer less than “[_1]” for the number of days to keep logs.', [ ~0 >> 1 ] );
    }

    return $days;
}

=head2 _validate_spam_score(SCORE) [PRIVATE]

=head3 ARGUMENTS

=over

=item SCORE - string

=back

=head3 RETURNS

number - integer

=head3 THROWS

=over

=item When the SCORE is not a number or has a fractional part.

=back

=cut

sub _validate_spam_score {
    my ($score) = @_;

    $score =~ s/\s//g if defined($score);

    if ( !defined($score) || $score !~ /^[-\.]?\d+(?:\.\d+)?$/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid value for minimum spam score: “[_1]”.', [$score] );
    }

    if ( $score > $MAX_SPAM_SCORE || $score < $MIN_SPAM_SCORE ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'You must enter a minimum spam score between “[_1]” and “[_2]”.', [ $MIN_SPAM_SCORE, $MAX_SPAM_SCORE ] );
    }

    $score *= 10;    # The score is stored without decimal for compatibility with Spam Assassin

    return int $score;
}

=head2 _get_account(EMAIL) [PRIVATE]

Looks up the email based on if logged in as WebMail or cPanel/

=head3 ARGUMENTS

=over

=item EMAIL - string

=back

=head3 RETURNS

string - the email address to use for further calls.

=cut

sub _get_account {
    my ($account) = @_;

    if ( $Cpanel::appname && $Cpanel::appname eq 'webmail' && $Cpanel::authuser ) {
        return $Cpanel::authuser;
    }

    return $account;
}

=head2 _is_auto_whitelist_disabled(EMAILDIR) [PRIVATE]

=head3 ARGUMENTS

=over

=item EMAILDIR - string

The directory where configuration is stored for an email address.

=back

=head3 RETURNS

Boolean - 0 if auto-whitelisting is disabled, 1 if auto-whitelisting is enabled.

=cut

sub _is_auto_whitelist_disabled {
    my ($emaildir) = @_;

    return ( -e $emaildir . '/.boxtrapperautowhitelistdisable' ) ? 0 : 1;
}

=head2 _assert_feature_enabled(PARAMS) [PRIVATE]

=head3 ARGUMENTS

=over

=item PARAMS - hashref

With the following properties:

=over

=item allow_demo - boolean

If true, it should be allowed in DEMO mode, if false, it should not be allowed in DEMO mode.

=back

=back

=head3 RETURNS

1 always, throws on errors.

=head3 THROWS

=over

=item When allow_demo is false and the cPanel account is configured in DEMO mode.

=item When the MailSend role is not availalbe on the the server.

=item When the 'boxtrapper' feature is not available to the cPanel user.

=back

=cut

sub _assert_feature_enabled {
    my ($params) = @_;

    if ( !$params->{'allow_demo'} && $Cpanel::CPDATA{'DEMO'} ) {
        die Cpanel::Exception->create_raw( locale()->maketext('Sorry, this feature is disabled in demo mode.') );
    }

    if ( !_role_is_enabled() || !Cpanel::hasfeature('boxtrapper') ) {
        die Cpanel::Exception->create_raw( locale()->maketext("The [asis,BoxTrapper] feature is not enabled for this account.") );
    }

    return 1;
}

=head2 _list_account_directories(EMAIL) [PRIVATE]

=head3 ARGUMENTS

=over

=item EMAIL - the email account we want to get path information for.

=back

=head3 RETURNS

List of three elements.

=over

=item [0] - string

Cpanel homedir path for the current cpanel account.

=item [1] - string

Path to where email related information is stored for the email account.

=item [2] - string

Path to the delivery directory for the email account.

=back

=head3 THROWS

=over

=item When the email account is not owned by the cPanel account.

=item When the email account does not exist.

=item When something goes wrong lookup up the directories for an email account.

=back

=cut

sub _list_account_directories {
    my ($account) = @_;

    my ($homedir) = BoxTrapper_getaccountinfo( $account, undef, { 'uapi' => 1, 'validate' => 1 } );

    if ( !$homedir ) {
        die Cpanel::Exception->create_raw( locale()->maketext( 'The system failed to locate the home directory for the email account, [_1].', $account ) );
    }

    my ( $emaildir, $deliverdir ) = BoxTrapper_getemaildirs(
        $account,
        $homedir,
        0,                                  # dont skip directory checks
        $Cpanel::CPDATA{'DEMO'} ? 1 : 0,    # create directories if they do not exist
        { 'uapi' => 1 }
    );

    if ( !$emaildir ) {
        die Cpanel::Exception->create_raw( locale()->maketext( 'The system experienced issues when it tried to access the email account, [_1].', $account ) );
    }

    return ( $homedir, $emaildir, $deliverdir );

}

our %API = (
    accountmanagelist => {
        needs_role       => 'MailReceive',
        allow_demo       => 1,
        worker_node_type => 'Mail',
    }
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
