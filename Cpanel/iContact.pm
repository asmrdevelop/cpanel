package Cpanel::iContact;

# cpanel - Cpanel/iContact.pm                      Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::ArrayFunc::Uniq              ();
use Cpanel::Exception                    ();
use Cpanel::FHUtils::Tiny                ();
use Cpanel::iContact::EventImportance    ();
use Cpanel::iContact::Providers          ();
use Cpanel::LoadModule::Custom           ();
use Cpanel::Debug                        ();
use Cpanel::Hostname                     ();
use Cpanel::Validate::EmailCpanel        ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::Domain::Tiny       ();
use Cpanel::Validate::VirtualUsername    ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::Config::HasCpUserFile        ();
use Cpanel::Config::LoadWwwAcctConf      ();
use Cpanel::iContact::Email              ();
use Cpanel::PwCache                      ();
use Cpanel::LoadModule                   ();
use Whostmgr::UI                         ();    # PPI USE OK - it is being used below, at least a little.

my $NON_ROOT_EVENT_PRIORITY = $Cpanel::iContact::EventImportance::DEFAULT_IMPORTANCE;

our $VERSION = '1.4';
our @LAST_ERRORS;

# internal hash of usernames, passwords, levels and state
my $LOG_KEEP_DAYS = 30;
my %CONTACTS;
my $optional_components;

sub clevels_file { return '/var/cpanel/clevels.conf' }

# This is the minimum EventImportance needed to
# send the notification
our %RECEIVES_NAME_TO_NUMBER = (
    'None'              => $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Disabled'},
    'HighOnly'          => $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'High'},
    'HighAndMediumOnly' => $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Medium'},
    'All'               => $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Low'},
);

our %ICONTACT_PROVIDERS = (
    'CONTACTUIN'        => 'Oscar',
    'CONTACTPUSHBULLET' => 'Pushbullet',
    'CONTACTEMAIL'      => 'Email',
    'CONTACTPAGER'      => 'Pager',
    'CONTACTSMS'        => 'SMS',
);

#----------------------------------------------------------------------
#Send out notifications in response to an event on
#the system. Also, by default, logs the notification to the main log.
#
#Named arguments:
#   - application (may also be spelled "app")
#       Will normally be one of the keys in default_contact_levels()'s response.
#       This is irrelevant for non-root notices except for logging and saving to disk.
#
#       default: 'Notice'
#
#   - event_name (string, OPTIONAL)
#       Used to look up the event’s importance level via EventImportance.pm
#       If not given, use the default importance for the "application" (above).
#       This is irrelevant for non-root notices except for logging and saving to disk.
#
#   - prepend_hostname_subject (boolean)
#       Switch to prefix the hostname onto the subject.
#       NOTE: Always enabled if "subject" is Perl-false-y.
#
#   - prepend_domain_subject (boolean)
#       Switch to prefix the hostname onto the subject.
#       NOTE: Always enabled if "subject" is Perl-false-y.
#
#   - email_only (boolean)
#       Switch to restrict notifications to CONTACTEMAIL only.
#
#   - to
#       The system user or Webmail account to receive the notification.
#       If a system user, this is the user whose notification settings to reference.
#       If a Webmail account, this functions as though for a user whose
#          CONTACTEMAIL.level were 3. It will also put the domain of this address
#          as part of the email’s subject.
#       If not given, we use root/system notifications.
#
#   - subaccount (string, optional)
#      The subaccount to use as the recipient of the notification. This must be
#      in user@domain format. Although the primary means of reaching a subaccount
#      is expected to be via email (whether their own cPanel email or the alternate
#      email that was filled in during account creation), this is not intended to
#      be the only way. Any available contact information for the subaccount may
#      be used for sending the notification.
#
#   - use_alternate_email (boolean, optional)
#      Instructs iContact to favor the alternate contact email rather than the primary
#      one. This is currently only supported for subaccounts.
#
#   - email (arrayref)
#       The email recipients of the message.
#       This will OVERRIDE the "to" setting insofar as destinations for the
#       message, but it will NOT override "to" for the From: header.
#
#   - subject
#       The subject of the message.
#       NOTE: If this is Perl-false-y, "prepend_hostname_subject" is always enabled.
#       NOTE: If this is Perl-false-y, "prepend_domain_subject" is always enabled.
#       Cannot contain CR, LF, or FF characters.
#
#       default: 'General Notice'
#
#   - im_subject (optional)
#       The subject of the message that is suitable to be passed to an
#       instant message client.
#       NOTE: If this is Perl-false-y, "prepend_hostname_subject" is always enabled.
#       NOTE: If this is Perl-false-y, "prepend_domain_subject" is always enabled.
#       Cannot contain CR, LF, or FF characters.
#
#       default: 'General Notice'
#
#   - from
#       The "from" of a message to root.
#       May not be sent if "to" is given.
#       Cannot contain CR, LF, or FF characters.
#
#       If there is no "@", interpreted as a name only, so the following will be
#       the message's "from":
#           "$from" <cpanel@$hostname>
#
#       If not given, defaults to:
#           "cPanel on $hostname" <cpanel@$hostname>
#
#   - message
#       The message content, or a filehandle that, when read, yields the message.
#       NOTE: ICQ notifications CANNOT read from filehandles.
#
#       Defaults to the message's subject (post-hostname-prefixing).
#
#   - im_message (optional)
#       The message content that is suitable for passing to an im client.
#
#       Defaults to the message's subject (post-hostname-prefixing).
#
#   - plaintext_message
#       Preferred for ICQ notifications over whatever "message" yields.
#
#   - quiet (boolean)
#       Suppress adding a note about the notification to the system log.
#       This flag is automatically set if $Whostmgr::UI::method eq 'hide'.
#
#   - team_account (boolean)
#       This is a team account and team_user's contact email is used to send notifictaions.
#       This flag is set whenever team user is created  with an activation email.
#
#   - content-type
#       The Content-Type header to indicate for the "message" in an email or pager notification.
#       Ignored for other message types.
#
#       Default is $Cpanel::iContact::Email::DEFAULT_CONTENT_TYPE.
#
#   - attach_files (arrayref, optional)
#       Attachments for an email notification.
#       Ignored for other notification types.
#       Each list item is a filesystem path
#
#   - html_related (arrayref, optional)
#       Passed through to Cpanel::Email::Object
#
#   - domain (optional)
#       If no from address is specificed the domain will
#       be used to.
#
#   - username (optional, required if 'to' is passed with an email)
#       The username of the account this notification is being
#       sent for.  This can be a system user or a webmail user.
#
#   - x_headers (optional, hashref)
#       Passed on to Cpanel::Email::Object
#
#
# TODO: Rename icontact to send_notification and add exceptions.
#       Then wrap icontact around it with exceptions trapped.
sub icontact {    ## no critic (ProhibitExcessComplexity)
    my %AGS = @_;

    # Avoid waiting on an integrity check when we just want to send a message
    #
    # Cheaply avoid a once warning in updatenow.static.
    local $Cpanel::SQLite::AutoRebuildBase::SKIP_INTEGRITY_CHECK;
    $Cpanel::SQLite::AutoRebuildBase::SKIP_INTEGRITY_CHECK = 1;

    my $app = delete $AGS{'application'} || delete $AGS{'app'} || 'Notice';

    my $event_name = delete $AGS{'event_name'};

    my $prepend_domain_subject   = delete $AGS{'prepend_domain_subject'}   || !$AGS{'subject'};
    my $prepend_hostname_subject = delete $AGS{'prepend_hostname_subject'} || !$AGS{'subject'};

    my $subject             = delete $AGS{'subject'} || 'General Notice';
    my $to                  = delete $AGS{'to'};
    my $subaccount          = delete $AGS{'subaccount'};
    my $use_alternate_email = delete $AGS{'use_alternate_email'};
    my $domain              = delete $AGS{'domain'};
    my $email_ar            = delete $AGS{'email'};
    my $msg                 = delete $AGS{'message'}           || q{};
    my $plaintext_msg       = delete $AGS{'plaintext_message'} || q{};
    my $im_msg              = delete $AGS{'im_message'}        || q{};
    my $im_subject          = delete $AGS{'im_subject'}        || q{};
    my $quiet               = delete $AGS{'quiet'}             || $Whostmgr::UI::method && $Whostmgr::UI::method eq 'hide';    # PPI NO PARSE - Only will be set if loaded
    my $email_only          = delete $AGS{'email_only'};
    my $html_related        = delete $AGS{'html_related'};
    my $username            = delete $AGS{'username'};
    my $x_headers           = delete $AGS{'x_headers'};
    my $team_account        = delete $AGS{'team_account'};
    my $attach_files        = normalize_attach_files( delete $AGS{'attach_files'} );

    my $content_type = delete $AGS{'content-type'} || $Cpanel::iContact::Email::DEFAULT_CONTENT_TYPE;

    #TODO: Re-enable this after we've ensured that it's safe.
    #if (%AGS) {
    #    die "Unrecognized argument(s): " . join( ' ', keys %AGS );
    #}

    my $hostname = Cpanel::Hostname::gethostname();

    if ( defined $email_ar ) {
        if ( ( ref $email_ar ) eq 'ARRAY' ) {
            die "Invalid “email”: [@$email_ar]" if grep { tr<\r\n\f><> } @$email_ar;
        }
        else {
            die "“email” must be undef or an arrayref!";
        }
    }
    else {
        $email_ar = [];
    }

    #TODO: Make this die() on invalid inputs instead of massaging them.
    $_ && s/[\r\n\f]*//g for ($subject);

    my $contactshash_ref;

    my $event_priority;

    # cPanel User && Team User contact settings
    if ( defined $to && length $to && ( !defined $subaccount || !length $subaccount ) ) {
        if ( $to ne 'root' && $to !~ m/\@/ ) {
            require Cpanel::Validate::Username::Core;

            #TODO: Make this die() on invalid input instead of massaging.
            $username = Cpanel::Validate::Username::Core::normalize($to);

            if ( !Cpanel::Config::HasCpUserFile::has_cpuser_file($username) ) {
                die "Nonexistent cPanel user specified in the “to” field: “$username”";
            }

            $contactshash_ref = _load_user_contactsettings($username);
        }

        # Team User check to send activation email
        elsif ( defined $team_account && $team_account && $to =~ /\@/ ) {
            $contactshash_ref = _load_team_contactsettings($to);
        }

        # Specific Email (probably a webmail user, but not required to be)
        elsif ( $to =~ m{\@} && Cpanel::Validate::EmailCpanel::is_valid($to) ) {

            #TODO: Make this die() instead.
            if ( !length $username ) {
                die "You must specify a cPanel user in the “username” field when the “to” field contains an “@”.";
            }

            $contactshash_ref = _load_email_contactsettings($to);

        }

        else {

            #TODO: Make this die() instead
            warn "Invalid “to”: $to";
            return;
        }

        $event_priority = $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'High'};
    }
    elsif ( length $subaccount ) {
        Cpanel::Validate::VirtualUsername::validate_or_die($subaccount);
        $contactshash_ref = _load_subaccount_contactsettings( $subaccount, $use_alternate_email );

        $event_priority = $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'High'};
    }

    # Sysadmin
    else {
        $contactshash_ref = _loadcontactsettings();
    }

    if ( !$event_priority ) {
        my $importance_obj = Cpanel::iContact::EventImportance->new();

        if ( defined $event_name && length $event_name ) {
            $event_priority = $importance_obj->get_event_importance( $app, $event_name );
        }
        else {
            $event_priority = $importance_obj->get_application_importance($app);
        }
    }

    # Email can overwrite $contactshash_ref
    if (@$email_ar) {
        $contactshash_ref->{'CONTACTEMAIL'}{'contact'} = $email_ar;
        $contactshash_ref->{'CONTACTEMAIL'}{'level'} ||= $RECEIVES_NAME_TO_NUMBER{'All'};
        $contactshash_ref->{'CONTACTEMAIL'}{'send'} = 1;
    }

    my $from_domain = $hostname;

    if ($prepend_domain_subject) {

        if ( length $domain && Cpanel::Validate::Domain::Tiny::validdomainname( $domain, 1 ) ) {
            $from_domain = $domain;
        }
        elsif ( length $username ) {
            if ( $username =~ m{@} ) {
                $from_domain = ( split( m{@}, $username, 2 ) )[1];
            }
            else {
                require Cpanel::AcctUtils::Domain;
                $from_domain = Cpanel::AcctUtils::Domain::getdomain($username);
            }
        }

        # just in case one of the above settings accidentally set undef or q{}
        $from_domain ||= $hostname;
    }

    # Will be the hostname if $prepend_domain_subject is not set
    $subject = "[$from_domain] $subject";
    if ($im_subject) {
        $im_subject = "[$from_domain] $im_subject";
    }

    # CPANEL-37533:
    # "From" string (not email addy) is now configurable.
    # REPLYTO email address is configurable.
    # Despite the email almost always explicitly saying "DO NOT REPLY TO THIS EMAIL" (lol),
    # people will inevitably reply. Allow the customer to set what they feel is necessary
    # to intercept these (or not).
    # Default to what we used to do in the absence of setting.
    my $default_email = qq{cpanel\@$from_domain};
    my $from          = $contactshash_ref->{'CONTACTEMAIL'}{'EMAILFROMNAME'} || $AGS{'from'} || qq{"cPanel on $from_domain"};
    my $replyto       = $contactshash_ref->{'CONTACTEMAIL'}{'EMAILREPLYTO'}  || $default_email;
    $replyto = "$from <$replyto>";
    $from    = "$from <$default_email>";

    if ( $ENV{'CPANEL_DEBUG_LEVEL'} && $ENV{'CPANEL_DEBUG_LEVEL'} >= 1 ) {
        print STDERR __PACKAGE__ . ": icontact app[$app\:\:$event_name] priority[$event_priority] from[$from] subject[$subject] msg[$msg] hostname[$hostname]\n";
    }

    # 0 == never
    return if !$event_priority;
    if ( $msg eq '' ) { $msg = $subject; }

    # Create array of keys to use in loop
    my @keys = sort keys %{$contactshash_ref};

    # Guard against logging/notifying for nonexistent providers injected into /etc/wwwacct.conf - CPANEL-10961
    # We have to augment our providers list here because the proper time to delete the bogus 'provider' from the $contactshash_ref is in the below loop context.
    # This move should be safe enough as we used to just be calling this below in _send_notification anyways (and it operates on a package scoped reference to a hash).
    Cpanel::iContact::Providers::augment_icontact_providers( \%ICONTACT_PROVIDERS );

    my %provider_conf;
    foreach my $contact_type (@keys) {
        next if $contact_type eq 'mtime';

        # The below fixes CPANEL-10961 (see first comment above loop)
        if ( !exists( $ICONTACT_PROVIDERS{$contact_type} ) ) {
            delete $contactshash_ref->{$contact_type};
            next;
        }
        else {

            # check for "dependant" fields and don't send if we aren't satisfied -- CPANEL-17316
            # TODO? Add ability to add 'dependencies' to non-pluggable modules?
            %provider_conf = Cpanel::iContact::Providers::get_settings() if !%provider_conf;
            if (   exists( $provider_conf{$contact_type} )
                && exists( $provider_conf{$contact_type}{'depends'} )
                && ref $provider_conf{$contact_type}{'depends'} eq 'ARRAY'
                && grep { !$contactshash_ref->{$contact_type}{$_} } @{ $provider_conf{$contact_type}{'depends'} } ) {
                delete $contactshash_ref->{$contact_type};
                next;
            }
        }

        # Exclude contact methods with a 'level' less than the
        # event priority
        #
        # For example
        # If the event_priority is 1 (High)
        # and the level for the contact is 2 (Medium AKA High and Medium only)
        # we want to send the event
        #  AKA exists && 3 < 2
        #
        # If the event_priority is 3 (Low)
        # and the level for the contact is 2 (Medium AKA High and Medium only)
        # we do NOT want to send the event
        #   AKA exists && 2 < 3
        next if defined( $contactshash_ref->{$contact_type}{'level'} ) && int( $contactshash_ref->{$contact_type}{'level'} ) < int($event_priority);

        # In email only mode we do not send to anything
        # that is not an email transport
        next if ( @$email_ar || $email_only ) && $contact_type ne 'CONTACTEMAIL';

        $contactshash_ref->{$contact_type}{'send'} = 1;
    }

    my @log;
  CONTACT:
    foreach my $contact (@keys) {
        my @required = qw(contact);

        if ( $contact eq 'CONTACTUIN' ) {
            push @required, 'user', 'password';
        }

        # Remove empty keys
        for my $req (@required) {
            my $c = $contactshash_ref->{$contact};
            if (   ( ref $c->{$req} && !@{ $c->{$req} } )
                || !exists $c->{$req}
                || !defined $c->{$req}
                || !length $c->{$req} ) {
                delete $contactshash_ref->{$contact};
                next CONTACT;
            }
        }

        next if $quiet;

        my $type = Cpanel::StringFunc::Trim::begintrim( $contact, 'CONTACT' );
        if ( $contactshash_ref->{$contact}{'send'} ) {
            my $contacts_string = $contactshash_ref->{$contact}{'contact'};
            if ( 'ARRAY' eq ref($contacts_string) ) {

                # For security we hide the last 5 characters of the address
                $contacts_string = join( ', ', map { my $copy = $_; $copy =~ s/.{5}$/\*\*\*\*\*/; $copy; } @$contacts_string );
            }
            push @log, { 'app' => $app, 'contacts_string' => $contacts_string, 'type' => $type, 'eventimportance' => $event_priority };
        }
    }

    my $to_ar = $contactshash_ref->{'CONTACTEMAIL'}{'contact'};

    #NOTE: $to_ar should probably always be an arrayref here, but just in case.
    if ( 'ARRAY' ne ref $to_ar ) {
        $to_ar = [$to_ar];
    }

    my %email_args = (
        to           => $to_ar,
        'Reply-To'   => $replyto,
        subject      => $subject,
        from         => $from,
        html_related => $html_related,
        application  => $app,
        event_name   => $event_name,
        x_headers    => $x_headers,
    );

    my $main_content_ref = Cpanel::FHUtils::Tiny::is_a($msg) ? $msg : \$msg;

    if ( length $im_msg ) {
        $email_args{'im_message'} = $im_msg;
    }
    if ( length $im_subject ) {
        $email_args{'im_subject'} = $im_subject;
    }

    if ( $content_type =~ m<html> ) {
        $email_args{'html_body'} = $main_content_ref;

        if ( length $plaintext_msg ) {
            $email_args{'text_body'} = \$plaintext_msg;
        }
    }
    else {
        $email_args{'text_body'} = $main_content_ref;
    }

    try {
        $email_args{'history_file'} = _save_notification_to_log(
            'log_user'      => ( $username || 'root' ),
            'app'           => $app,
            'email_args_hr' => \%email_args,
        );
    }
    catch {
        $username //= '';
        Cpanel::Debug::log_info( "Failed to save notification for “$username” because of an error: " . Cpanel::Exception::get_string($_) );
    };

    # No contact needed, but save it in the log so we
    # can view it later if we want to.
    return if !@$to_ar || !grep { $contactshash_ref->{$_}{'send'} } @keys;

    foreach my $log (@log) {

        # This is legacy behavior.
        # It would be nice to refactor this entire function, however
        # that would drastically increase scope so it has been deferred.
        my $log_level_name = $log->{'eventimportance'} == $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'High'} ? 'High' : $log->{'eventimportance'} == $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Medium'} ? 'Medium' : $log->{'eventimportance'} == $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{'Low'} ? 'Low' : 'Unknown';

        Cpanel::Debug::log_info( "$app\:\:" . ( $event_name || '' ) . " Notification => $log->{'contacts_string'} via $log->{'type'} [eventimportance => $log_level_name ($log->{'eventimportance'})]" );

    }

    my $notifications = _send_notifications( $contactshash_ref, \%email_args, $attach_files );

    return { 'notifications' => $notifications };
}

sub _send_notifications {
    my ( $contactshash_ref, $email_args_hr, $attach_files_ar ) = @_;

    my @NOTIFICATIONS;
    local $SIG{'PIPE'} = sub {
        print STDERR __PACKAGE__ . ": icontact broken pipe\n";
    };

    # Clear any errors that may have been previously set
    @LAST_ERRORS = ();
    foreach my $contact_type ( sort keys %{$contactshash_ref} ) {
        my $type = $contact_type;
        next if !( $type =~ s{^CONTACT}{} );
        next if $type !~ m{^[A-Za-z]+$};                          # only accept valid keys
        next if !$contactshash_ref->{$contact_type}{'send'};
        next if !$contactshash_ref->{$contact_type}{'contact'};

        my $to_ar = $contactshash_ref->{$contact_type}{'contact'};

        #NOTE: $to_ar should probably always be an arrayref here, but just in case.
        if ( 'ARRAY' ne ref $to_ar ) {
            $to_ar = [$to_ar];
        }
        $to_ar = [ map { "<$_>" } @$to_ar ] if $contact_type eq 'CONTACTEMAIL';
        $email_args_hr->{'to'} = $to_ar;

        my $module = $ICONTACT_PROVIDERS{$contact_type};

        push @NOTIFICATIONS, { 'type' => $type, 'contact' => $contactshash_ref->{$contact_type}{'contact'} };

        print STDERR __PACKAGE__ . ": icontact sending notification to $type.\n" if $ENV{'CPANEL_DEBUG_LEVEL'} && $ENV{'CPANEL_DEBUG_LEVEL'} >= 1;

        try {
            my $perl_module = "Cpanel::iContact::Provider::$module";
            Cpanel::LoadModule::Custom::load_perl_module($perl_module);
            my $obj = "$perl_module"->new(
                'contact'      => $contactshash_ref->{$contact_type},
                'args'         => $email_args_hr,
                'attach_files' => $attach_files_ar
            );
            $obj->send();
        }
        catch {
            my $err_str = "Failed to send notification of type “$type”: " . Cpanel::Exception::get_string($_);
            Cpanel::Debug::log_warn($err_str);

            # Set it somewhere it can actually be consulted outside of here
            push @LAST_ERRORS, $err_str;
        };
        delete $contactshash_ref->{$type}{'send'};
    }

    return \@NOTIFICATIONS;
}

sub reloadcontacts {
    %CONTACTS = %{ _loadcontactsettings(1) };
    return;
}

sub contact_descriptions {
    $INC{'Cpanel/Locale.pm'} or die("Cpanel::Locale is not loaded");    # DO NOT use L:MT in this file!!! This will cause a mess of undesireable dependencies.

    my $locale = shift or die("Not passed a \$locale object!");

    my $old_ctx = $locale->set_context_plain();

    my $two_gibibytes = 2 * ( 2**30 );

    # Note: Do not list user notifications here as they have their own controls
    #
    # For example:
    # ChangePassword
    # bwlimit
    # login
    # fullbackup
    #
    # These settings can all go to a user other than root.  If they are listed here
    # root can inadvertently disable them leaving the user wondering where their
    # notification went.
    #

    my %contact_descriptions = (

        'Accounts' => {
            display_name => $locale->maketext('Digest Authentication Disabled Due to Account Rename'),
        },
        'Accounts::ChildDedistributionSuccess' => {
            display_name => $locale->maketext('Transfer Offloaded Functionality from a Child Node Success'),
        },
        'Accounts::ChildDedistributionFailure' => {
            display_name => $locale->maketext('Transfer Offloaded Functionality from a Child Node Failure'),
        },
        'Accounts::ChildDistributionSuccess' => {
            display_name => $locale->maketext('Offload Functionality to a Child Node Success'),
        },
        'Accounts::ChildDistributionFailure' => {
            display_name => $locale->maketext('Offload Functionality to a Child Node Failure'),
        },
        'Accounts::ChildRedistributionSuccess' => {
            display_name => $locale->maketext('Transfer Offloaded Functionality between Child Nodes Success'),
        },
        'Accounts::ChildRedistributionFailure' => {
            display_name => $locale->maketext('Transfer Offloaded Functionality between Child Nodes Failure'),
        },
        'AdminBin' => {
            display_name => $locale->maketext('Backup Failure'),
        },
        'Backup' => {
            display_name => $locale->maketext('[asis,cPanel] Backup'),
        },
        'Backup::Delayed' => {
            display_name => $locale->maketext('Backup Delayed'),
            help_text    => $locale->maketext('This option indicates that the backup process continues to run after 16 hours.'),
        },
        'Backup::Disabled' => {
            display_name => $locale->maketext('[asis,cPanel] Backup Destination Disabled'),
        },
        'Backup::Failure' => {
            display_name => $locale->maketext('Backup Failed To Finish'),
            help_text    => $locale->maketext('This option indicates that the backup failed.'),
        },
        'Backup::PartialFailure' => {
            display_name => $locale->maketext('Backup Finished With Partial Failure'),
            help_text    => $locale->maketext('This option indicates that the backup completed with errors.'),
        },
        'Backup::PreBackupNotice' => {
            display_name => $locale->maketext('Scheduled Backup Will Start Soon'),
        },
        'Backup::Success' => {
            display_name => $locale->maketext('Backup Successful'),    # case 192249 ensure the word backup comes first for sort order
        },
        'Backup::Transport' => {
            display_name => $locale->maketext('Backup Transport Error'),
            help_text    => $locale->maketext('This option indicates the system failed to transport the backup to the remote destination.'),
        },
        'BandwidthUsageExceeded' => {
            display_name => $locale->maketext('Bandwidth Limits'),
            help_text    => $locale->maketext(
                'This option will trigger no actions when the Tweak Setting “[_1]” has been disabled.',
                'Send bandwidth limit notification emails',    # Not translated
            ),
        },
        'ChangePassword' => {
            display_name => $locale->maketext('[asis,cPanel] Account Password'),
        },
        'Check::Biglog' => {
            display_name => $locale->maketext( 'System Log Approaches [format_bytes,_1]', $two_gibibytes ),
        },
        'Check::CpanelPackages' => {
            display_name => $locale->maketext('Altered Cpanel Packages Check'),
        },
        'Check::EximConfig' => {
            display_name => $locale->maketext('[asis,Exim] Update Failures'),
        },
        'Check::Hack' => {
            display_name => $locale->maketext('Root Compromise Checks'),
        },
        'Check::IP' => {
            display_name => $locale->maketext('[asis,IP] Address [asis,DNS] Check'),
        },
        'Check::ImmutableFiles' => {
            display_name => $locale->maketext('Update Failure Due to Immutable Files'),
        },
        'Check::InvalidDomains' => {
            display_name => $locale->maketext('Invalid Domains'),
        },
        'Check::MySQL' => {
            display_name => $locale->maketext('Corrupt Database Tables'),
        },
        'Check::MysqlConnection' => {
            display_name => $locale->maketext('Remote [asis,MySQL] Connection Failure'),
        },
        'Check::Oops' => {
            display_name => $locale->maketext('Kernel Crash Check'),
        },
        'Check::SSLCertExpired' => {
            display_name => $locale->maketext('Service [asis,SSL] Certificate Expiration'),
            help_text    => $locale->maketext("This option indicates that a system service SSL certificate is expired."),
        },
        'Check::SSLCertExpiresSoon' => {
            display_name => $locale->maketext('Service [asis,SSL] Certificate Expires Soon'),
            help_text    => $locale->maketext( "This option indicates that a system service SSL certificate will expire within [quant,_1,day,days].", 20 ),
        },
        'Check::Smart' => {
            display_name => $locale->maketext('Disk Integrity Check'),
        },
        'Check::ValidServerHostname' => {
            display_name => $locale->maketext('Invalid Hostname For Main [asis,IP] Address'),
        },
        'Check::UnmonitoredEnabledServices' => {
            display_name => $locale->maketext('Unmonitored Services'),
        },
        'Check::SecurityAdvisorStateChange' => {
            display_name => $locale->maketext('Security Advisor State Change'),
        },
        'Check::HostnameOwnedByUser' => {
            display_name => $locale->maketext('Hostname conflicts with a cPanel user account'),
        },
        'Check::Resolvers' => {
            display_name => $locale->maketext('[asis,DNS] Resolver Performance Issues'),
        },
        'Check::PdnsConf' => {
            display_name => $locale->maketext('Migrate [asis,PowerDNS] configuration upon upgrade'),
        },
        'Check::LocalConfTemplate' => {
            display_name => $locale->maketext('Local configuration template detected upon service upgrade'),
        },
        'CloudLinux' => {
            display_name => $locale->maketext('[asis,CloudLinux] License Detected'),
        },
        'Config' => {
            display_name => $locale->maketext('[asis,cPanel] Configuration Checks'),
        },
        'ConvertAddon' => {
            display_name => $locale->maketext('Convert Addon Domain to Account Notifications'),
        },
        'dbindex::Warn' => {
            display_name => $locale->maketext('[asis,dbindex] Cache File Out of Date'),
        },
        'DigestAuth' => {
            display_name => $locale->maketext('Forced Disable of Digest Auth'),
        },
        'DnsAdmin::ClusterError' => {
            display_name => $locale->maketext('[asis,DNS] Cluster Error'),
        },
        'DnsAdmin::UnreachablePeer' => {
            display_name => $locale->maketext('Lost Contact With [asis,DNS] Cluster'),
        },
        'DnsAdmin::DnssecError' => {
            display_name => $locale->maketext('[asis,DNSSEC] key synchronization failure'),
            help_text    => $locale->maketext("This option indicates that the system encountered an error during a [asis,DNSSEC] key synchronization on the [asis,cPanel] [asis,DNS] cluster."),
        },
        'Solr::Maintenance' => {
            display_name => $locale->maketext('[asis,Dovecot] [asis,Solr] maintenance task errors.'),
            help_text    => $locale->maketext("This option indicates that the system encountered an error during the [asis,Apache] [asis,Solr] maintenance task."),
        },
        'EasyApache' => {
            display_name => $locale->maketext('[asis,EasyApache] Configuration'),
        },
        'EasyApache::EA4_TemplateCheckUpdated' => {
            display_name => $locale->maketext('[asis,EasyApache 4] template updated'),
        },
        'EasyApache::EA4_ConflictRemove' => {
            display_name => $locale->maketext('[asis,EasyApache 4] conflict removed[comment,label text]'),
        },
        'Notice' => {
            display_name => $locale->maketext('Uncategorized'),
        },
        'Greylist' => {
            display_name => $locale->maketext('[asis,Greylist] System Changes'),
        },
        'InitialWebsite::Creation' => {
            display_name => $locale->maketext('Initial Website Creation'),
        },
        'Install::CheckcPHulkDB' => {
            display_name => $locale->maketext('[asis,cPHulk] Database Integrity Notices'),
        },
        'Install::PackageExtension' => {
            display_name => $locale->maketext('Package Extension Name Conflicts'),
        },
        'Install::FixcPHulkConf' => {
            display_name => $locale->maketext('[asis,cPHulk] Configuration Issues'),
        },
        'Install::CheckRemoteMySQLVersion' => {
            display_name => $locale->maketext('Remote [asis,MySQL] Server Notifications'),
        },
        'Logd' => {
            display_name => $locale->maketext('Bandwidth Data Processing Timeout'),
        },
        'Logger' => {
            display_name => $locale->maketext('Script Terminated Due to Deprecated Call'),
        },
        'Market' => {
            display_name => $locale->maketext('Notices concerning goods and services purchased via the [asis,cPanel] Market'),
        },
        'Market::SSLWebInstall' => {
            display_name => $locale->maketext('Installation of purchased [asis,SSL] certificates'),
            help_text    => $locale->maketext('This option indicates that an SSL certificate purchased via the SSL/TLS Wizard has been installed.'),
        },
        'Market::WHMPluginInstall' => {
            display_name => $locale->maketext('Installation of purchased [asis,WHM] Plugins.'),
        },

        #----------------------------------------------------------------------
        # In order to accommodate the consolidation of control of
        # AutoSSL::CertificateExpiring from notify_expiring_certificates into
        # autossl, AutoSSL notifications can go to user AND/OR root
        'AutoSSL::CertificateExpiring' => {
            display_name => $locale->maketext('[asis,AutoSSL] cannot request a certificate because all of the website’s domains have failed [output,abbr,DCV,Domain Control Validation].'),
            help_text    => $locale->maketext( 'This setting takes effect only when “[_1]” is enabled in WHM’s “[_2]” interface.', $locale->maketext('Notify when [asis,AutoSSL] cannot request a certificate because all domains on the website have failed [output,abbr,DCV,Domain Control Validation].'), $locale->maketext('Manage AutoSSL') ),
        },
        'AutoSSL::CertificateExpiringCoverage' => {
            display_name => $locale->maketext('[asis,AutoSSL] has deferred normal certificate renewal because a domain on the current certificate has failed [output,abbr,DCV,Domain Control Validation].'),
            help_text    => $locale->maketext( 'This setting takes effect only when “[_1]” is enabled in WHM’s “[_2]” interface.', $locale->maketext('Notify when [asis,AutoSSL] defers certificate renewal because a domain on the current certificate has failed [output,abbr,DCV,Domain Control Validation].'), $locale->maketext('Manage AutoSSL') ),

        },
        'AutoSSL::CertificateRenewalCoverage' => {
            display_name => $locale->maketext('[asis,AutoSSL] will not secure new domains because a domain on the current certificate has failed [output,abbr,DCV,Domain Control Validation], and the certificate is not yet in the renewal period.'),
            help_text    => $locale->maketext( 'This setting takes effect only when “[_1]” is enabled in WHM’s “[_2]” interface.', $locale->maketext('Notify when [asis,AutoSSL] will not secure new domains because a domain on the current certificate has failed [output,abbr,DCV,Domain Control Validation].'), $locale->maketext('Manage AutoSSL') ),
        },
        'AutoSSL::CertificateInstalled' => {
            display_name => $locale->maketext('[asis,AutoSSL] has installed a certificate successfully.'),
            help_text    => $locale->maketext( 'This setting takes effect only when “[_1]” is enabled in WHM’s “[_2]” interface.', $locale->maketext('Notify when [asis,AutoSSL] has renewed a certificate successfully.'), $locale->maketext('Manage AutoSSL') ),
        },
        'AutoSSL::CertificateInstalledReducedCoverage' => {
            display_name => $locale->maketext('[asis,AutoSSL] has renewed a certificate, but the new certificate lacks at least one domain that the previous certificate secured.'),
            help_text    => $locale->maketext( 'This setting takes effect only when “[_1]” is enabled in WHM’s “[_2]” interface.', $locale->maketext('Notify when [asis,AutoSSL] has renewed a certificate and the new certificate lacks at least one domain that the previous certificate secured.'), $locale->maketext('Manage AutoSSL') ),
        },
        'AutoSSL::CertificateInstalledUncoveredDomains' => {
            display_name => $locale->maketext('[asis,AutoSSL] has renewed a certificate, but the new certificate lacks one or more of the website’s domains.'),
            help_text    => $locale->maketext( 'This setting takes effect only when “[_1]” is enabled in WHM’s “[_2]” interface.', $locale->maketext('Notify when [asis,AutoSSL] has renewed a certificate and the new certificate lacks one or more of the website’s domains.'), $locale->maketext('Manage AutoSSL') ),
        },
        'AutoSSL::DynamicDNSNewCertificate' => {
            display_name => $locale->maketext('[asis,AutoSSL] has provisioned a new certificate for a dynamic [asis,DNS] domain.'),
        },

        #----------------------------------------------------------------------
        'SSL::CertificateExpiring' => {
            display_name => $locale->maketext('[asis,SSL] certificates expiring'),
            help_text    => $locale->maketext('This option indicates that a non-[asis,AutoSSL] certificate will expire soon.'),
        },
        'SSL::LinkedNodeCertificateExpiring' => {
            display_name => $locale->maketext('Hostname’s [asis,SSL] certificate expiring on a linked node'),
        },
        'SSL::CheckAllCertsWarnings' => {
            display_name => $locale->maketext('[asis,cPanel] service [asis,SSL] certificate warnings'),
            help_text    => $locale->maketext('This option indicates that a warning was generated while checking the [asis,cPanel] service [asis,SSL] certificates.'),
        },
        'Notice' => {
            display_name => $locale->maketext('Generic Notifications'),
        },
        'OutdatedSoftware::Notify' => {
            display_name => $locale->maketext('Notifications of Outdated Software'),
        },
        'OverLoad::CpuWatch' => {
            display_name => $locale->maketext('Stalled Process Notifications'),
        },
        'OverLoad::LogRunner' => {
            display_name => $locale->maketext('Stalled Statistics and Bandwidth Process Notifications'),
        },
        'Quota::Broken' => {
            display_name => $locale->maketext('Filesystem quotas are currently broken.'),
        },
        'Quota::DiskWarning' => {
            display_name => $locale->maketext('User Disk Usage Warning'),
        },
        'Quota::MailboxWarning' => {
            display_name => $locale->maketext('Mailbox Usage Warning'),
        },
        'Quota::RebootRequired' => {
            display_name => $locale->maketext('Reboot To Enable Filesystem Quotas Reminder'),
        },
        'Quota::SetupComplete' => {
            display_name => $locale->maketext('Filesystem Quotas Ready'),
        },
        'RPMVersions' => {
            display_name => $locale->maketext('Conversion of [asis,cpupdate.conf] settings to [asis,local.versions]'),
        },
        'StuckScript' => {
            display_name => $locale->maketext('Stuck Script'),
        },
        'SSHD::ConfigError' => {
            display_name => $locale->maketext('[asis,SSHD] Configuration Error'),
        },
        'TwoFactorAuth::UserEnable' => {
            display_name => $locale->maketext('User Enabled Two-Factor Authentication'),
        },
        'TwoFactorAuth::UserDisable' => {
            display_name => $locale->maketext('User Disabled Two-Factor Authentication'),
        },
        'Update::Blocker' => {
            display_name => $locale->maketext('Update Version Blocker'),
        },
        'Update::ServiceDeprecated' => {
            display_name => $locale->maketext('Update Blocker - Service Deprecation Notice'),
        },
        'Update::Now' => {
            display_name => $locale->maketext('Update Failures'),
        },
        'appconfig' => {
            display_name => $locale->maketext('[asis,AppConfig] Registration Notifications'),
        },
        'cPHulk' => {
            display_name => $locale->maketext('[asis,cPHulkd] Notifications'),
        },
        'cPHulk::BruteForce' => {
            display_name => $locale->maketext('[asis,cPHulkd] Brute Force'),
        },
        'cPHulk::Login' => {
            display_name => $locale->maketext('[asis,cPHulkd] Login Notifications'),
            help_text    => $locale->maketext('This option will trigger no actions when [asis,cPHulkd] is disabled.'),
        },
        'chkservd' => {
            display_name => $locale->maketext('Service failures ([asis,ChkServd])'),
        },
        'chkservd::DiskUsage' => {
            display_name => $locale->maketext('Disk Usage Warnings'),
        },
        'chkservd::Hang' => {
            display_name => $locale->maketext('Hung Service Checks'),
        },
        'MailServer::OOM' => {
            display_name => $locale->maketext('Mail Server Out of Memory'),
        },
        'Mail::ClientConfig' => {
            display_name => $locale->maketext('Email Client Configuration'),
        },
        'Mail::HourlyLimitExceeded' => {
            display_name => $locale->maketext('Maximum Hourly Emails Exceeded'),
        },
        'Mail::ReconfigureCalendars' => {
            display_name => $locale->maketext('Reconfigure CalDAV/CardDAV clients'),
        },
        'Mail::SendLimitExceeded' => {
            display_name => $locale->maketext('Outgoing Email Threshold Exceeded'),
        },
        'Mail::SpammersDetected' => {
            display_name => $locale->maketext('Large Amount of Outbound Email Detected'),
        },
        'chkservd::OOM' => {
            display_name => $locale->maketext('System Out of Memory'),
        },
        'cpbackup' => {
            display_name => $locale->maketext('[asis,cPanel] Backup (legacy notification)'),
        },
        'cpbackupdisabled' => {
            display_name => $locale->maketext('[asis,cPanel] Backup Destination Disabled (legacy notification)'),
        },
        'iContact' => {
            display_name => $locale->maketext('Instant Message Failure'),
        },
        'installbandwidth' => {
            display_name => $locale->maketext('Bandwidth File Conversion Disk Space Failure'),
        },
        'killacct' => {
            display_name => $locale->maketext('Account Removal'),
        },
        'parkadmin' => {
            display_name => $locale->maketext('Notification of New Addon Domains'),
        },
        'queueprocd' => {
            display_name => $locale->maketext('[asis,queueprocd] Critical Errors'),
        },
        'rpm.versions' => {
            display_name => $locale->maketext('Conversion of [asis,cpupdate.conf] Settings to [asis,local.versions] (legacy notification)'),
        },
        'suspendacct' => {
            display_name => $locale->maketext('Account Suspensions'),
        },
        'sysup' => {
            display_name => $locale->maketext('System Update Failures'),
        },
        'unsuspendacct' => {
            display_name => $locale->maketext('Account Unsuspensions'),
        },
        'upacct' => {
            display_name => $locale->maketext('Account Upgrades/Downgrades'),
        },
        'upcp' => {
            display_name => $locale->maketext('[asis,cPanel] Update Failures'),
        },
        'wwwacct' => {
            display_name => $locale->maketext('Account Creation'),
        },
        'Stats' => {
            display_name => $locale->maketext('Stats and Bandwidth Processing Errors'),
        },
        'PHPFPM::AccountOverquota' => {
            display_name => $locale->maketext('[asis,PHP-FPM] Account is over quota.'),
        },
        'Update::EndOfLife' => {
            display_name => $locale->maketext('[asis,cPanel] [output,amp] [asis,WHM] End of Life Notice'),
        },
        'DemoMode::MailChildNodeExists' => {
            display_name => $locale->maketext('Accounts with demo mode restrictions enabled and mail distributed to a child node.'),
        },
        'Application' => {
            display_name => $locale->maketext('Uncategorized Notifications'),
        },
    );

    Cpanel::LoadModule::load_perl_module('Cpanel::Component');
    $optional_components ||= Cpanel::Component->init();
    my $additional_descriptions = $optional_components->contact_descriptions( 'whm', $locale );
    foreach my $system_name ( keys %$additional_descriptions ) {
        next if $contact_descriptions{$system_name};    # do not let plugins overwrite builtins
        $contact_descriptions{$system_name} = $additional_descriptions->{$system_name};
    }

    $locale->set_context($old_ctx);

    return %contact_descriptions;
}

sub _load_user_contactsettings {
    my $user    = shift;
    my $homedir = Cpanel::PwCache::gethomedir($user);
    my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 3 ];
    my %USER_CONTACTS;
    return {} if !$uid;

    my $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    $USER_CONTACTS{'CONTACTEMAIL'}{'level'}   = $RECEIVES_NAME_TO_NUMBER{'All'};
    $USER_CONTACTS{'CONTACTEMAIL'}{'contact'} = $cpuser_data->contact_emails_ar();

    if ( $cpuser_data->{'PUSHBULLET_ACCESS_TOKEN'} ) {
        $USER_CONTACTS{'CONTACTPUSHBULLET'}{'level'}   = $RECEIVES_NAME_TO_NUMBER{'All'};
        $USER_CONTACTS{'CONTACTPUSHBULLET'}{'send'}    = 1;
        $USER_CONTACTS{'CONTACTPUSHBULLET'}{'contact'} = [ $cpuser_data->{'PUSHBULLET_ACCESS_TOKEN'} ];
    }

    return \%USER_CONTACTS;
}

sub _load_email_contactsettings {
    my ($email) = @_;

    my %USER_CONTACTS = (
        'CONTACTEMAIL' => {
            'level'   => $RECEIVES_NAME_TO_NUMBER{'All'},
            'contact' => [$email],
            'send'    => 1,
        }
    );

    my ( $email_user, $domain ) = split( m{@}, $email, 2 );
    if ( Cpanel::Validate::FilesystemNodeName::is_valid($email_user) && Cpanel::Validate::FilesystemNodeName::is_valid($domain) ) {
        my $webmail_accounts_cpanel_user;
        try {
            require Cpanel::AcctUtils::Lookup;
            $webmail_accounts_cpanel_user = Cpanel::AcctUtils::Lookup::get_system_user($email);
        };
        if ($webmail_accounts_cpanel_user) {
            require Cpanel::AccessIds::ReducedPrivileges;
            require Cpanel::DataStore;
            my $homedir   = Cpanel::PwCache::gethomedir($webmail_accounts_cpanel_user);
            my $base_path = "$homedir/etc/$domain/$email_user";
            my $cf;

            # TODO prevent this from loading a large file
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                $webmail_accounts_cpanel_user,
                sub {
                    $cf = Cpanel::DataStore::fetch_ref( $base_path . '/.cpanel/contactinfo' );
                }
            );

            if ($cf) {

                if ( $cf->{'pushbullet_access_token'} ) {
                    $USER_CONTACTS{'CONTACTPUSHBULLET'}{'level'}   = $RECEIVES_NAME_TO_NUMBER{'All'};
                    $USER_CONTACTS{'CONTACTPUSHBULLET'}{'send'}    = 1;
                    $USER_CONTACTS{'CONTACTPUSHBULLET'}{'contact'} = [ $cf->{'pushbullet_access_token'} ];
                }
                foreach my $email_key (qw(email second_email)) {
                    if ( $cf->{$email_key} && grep { $cf->{$email_key} ne $_ } @{ $USER_CONTACTS{'CONTACTEMAIL'}{'contact'} } ) {
                        push @{ $USER_CONTACTS{'CONTACTEMAIL'}{'contact'} }, $cf->{$email_key};
                    }
                }

            }
        }
    }

    return \%USER_CONTACTS;
}

sub _load_team_contactsettings {
    my $team_user_name = shift;

    Cpanel::LoadModule::load_perl_module('Cpanel::Team::Config');
    my $team_user     = Cpanel::Team::Config::get_team_user($team_user_name);
    my @emails        = grep { length } @{$team_user}{qw (contact_email secondary_contact_email )};
    my %USER_CONTACTS = (
        'CONTACTEMAIL' => {
            'level'   => $RECEIVES_NAME_TO_NUMBER{'All'},
            'contact' => \@emails,
            'send'    => 1,
        }
    );
    return \%USER_CONTACTS;
}

sub _load_subaccount_contactsettings {
    my ( $full_username, $use_alternate_email ) = @_;
    my ( $username, $domain ) = split /\@/, $full_username, 2;
    my %SUBACCOUNT_CONTACTS;

    require Cpanel::AcctUtils::Lookup;
    my $owner_of_subaccount = Cpanel::AcctUtils::Lookup::get_system_user($full_username);
    if ($owner_of_subaccount) {

        # The code below queries an untrusted SQLite database using DBD::SQLite.
        # Please check with the security team before switching Cpanel::AccessIds::do_as_user
        # to Cpanel::AccessIds::ReducedPrivileges::call_as_user here.
        require Cpanel::AccessIds;
        my (@contact_emails) = Cpanel::AccessIds::do_as_user(    # do not use call_as_user; only do_as_user
            $owner_of_subaccount,
            sub {
                my @email_addresses;
                {
                    eval 'require Cpanel::UserManager::Storage';    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -- hide from perlpkg

                    my $alternate_email;
                    my $subaccounts_local_email_address;
                    {
                        my $dbh = Cpanel::UserManager::Storage::dbh();

                        # Check to see whether the subaccount has a linked email service account,
                        # which means it can receive email locally on this server.
                        my $annotation_list  = Cpanel::UserManager::Storage::list_annotations( full_username => $full_username, 'dbh' => $dbh );
                        my $email_annotation = $annotation_list->lookup_by( $full_username, 'email' );
                        if ( $email_annotation && $email_annotation->merged ) {
                            $subaccounts_local_email_address = $full_username;
                        }

                        # Check to see whether the subaccount has an alternate email address configured.
                        # This is needed for password reset to work.
                        my $record_obj = Cpanel::UserManager::Storage::lookup_user(
                            username => $username,
                            domain   => $domain,
                            dbh      => $dbh
                        );
                        $alternate_email = $record_obj->alternate_email;
                    }

                    # use_alternate_email must be set in the case of a password reset.
                    # Other general notifications should leave it up to this function to
                    # pick the best contact email.
                    if ( $use_alternate_email || !$subaccounts_local_email_address ) {
                        push @email_addresses, $alternate_email;
                    }
                    else {
                        push @email_addresses, $subaccounts_local_email_address;
                    }

                    require Cpanel;

                    # Hide this from perlpkg since it’s only useful
                    # when there are accounts, and there are no accounts
                    # during initial install.
                    Cpanel::LoadModule::load_perl_module('Cpanel::CustInfo::Impl');

                    Cpanel::initcp();
                    my $results = Cpanel::CustInfo::Impl::fetch_addresses(
                        appname    => $Cpanel::appname || $Cpanel::appname,    # avoid warning used once
                        cpuser     => $Cpanel::user    || $Cpanel::user,       # avoid warning used once
                        cphomedir  => $Cpanel::homedir,
                        username   => $full_username,
                        no_default => 1,
                    );
                    foreach my $result (@$results) {
                        if ( $result->{name} eq 'email' ) {
                            push @email_addresses, $result->{value};
                        }
                        if ( $result->{name} eq 'second_email' ) {
                            push @email_addresses, $result->{value};
                        }
                    }
                }
                return @email_addresses;
            }
        );

        @contact_emails = grep { $_ } @contact_emails;
        @contact_emails = Cpanel::ArrayFunc::Uniq::uniq(@contact_emails);

        if (@contact_emails) {
            $SUBACCOUNT_CONTACTS{'CONTACTEMAIL'} = {
                'contact' => \@contact_emails,
                'send'    => 1,
                'level'   => $RECEIVES_NAME_TO_NUMBER{'All'},
            };
        }
    }
    if ( !%SUBACCOUNT_CONTACTS ) {
        die 'No contact email address could be found for ' . $full_username . "\n";
    }
    return \%SUBACCOUNT_CONTACTS;
}

sub _loadcontactsettings {
    require Cpanel::ContactInfo::Email;
    my $reload = shift || 0;

    if ( !$reload && exists( $CONTACTS{'mtime'} ) ) {

        # Check mtime and possibly force a reload
        my $mtime;
        foreach my $file ( keys %{ $CONTACTS{'mtime'} } ) {
            $mtime = ( stat($file) )[9];
            if ( !$mtime || $CONTACTS{'mtime'}{$file} != $mtime ) {
                $reload = 1;
                last;
            }
        }
        return \%CONTACTS;
    }

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    foreach my $key ( keys %{$wwwacct_ref} ) {
        next if !length $wwwacct_ref->{$key};

        if ( $key =~ m/^CONTACT([A-Z]*)/ ) {
            my $type = $1;
            if ( $type eq 'EMAIL' || $type eq 'PAGER' ) {
                $CONTACTS{$key}{'contact'} = [ grep( !m/^\s*$/, Cpanel::ContactInfo::Email::split_multi_email_string( $wwwacct_ref->{$key} ) ) ];
            }
            else {
                $CONTACTS{$key}{'contact'} = [ grep( !m/^\s*$/, split( /\s*,\s*/, $wwwacct_ref->{$key} ) ) ];
            }
        }
    }

    # COBRA-3872: for third party providers, let's augment their contact hashref with non-CONTACT prefixed wwwacct_ref values
    Cpanel::iContact::Providers::augment_contact_settings( $wwwacct_ref, \%CONTACTS );

    if ( length $wwwacct_ref->{'ICQPASS'} && length $wwwacct_ref->{'ICQUSER'} ) {
        $CONTACTS{'CONTACTUIN'}{'password'} = $wwwacct_ref->{'ICQPASS'};
        $CONTACTS{'CONTACTUIN'}{'user'}     = $wwwacct_ref->{'ICQUSER'};
    }
    foreach (qw{EMAILREPLYTO EMAILFROMNAME}) {
        $CONTACTS{'CONTACTEMAIL'}{$_} = $wwwacct_ref->{$_} if length $wwwacct_ref->{$_};
    }

    augment_contacts_with_default_levels( \%CONTACTS );

    my $clevels = clevels_file();
    $CONTACTS{'mtime'}{$clevels} = ( stat($clevels) )[9];
    if ( open my $clevels_fh, '<', $clevels ) {
        while (<$clevels_fh>) {
            chomp;
            s/\r//g;
            if (m/^(CONTACT\S+)\s+(\S+)/) {
                my $contacttype = $1;
                my $level       = $2;
                next if ( $level eq '' );
                $CONTACTS{$contacttype}{'level'} = $level;
            }
        }
        close $clevels_fh;
    }

    my $hostname   = Cpanel::Hostname::gethostname();
    my $root_email = 'root@' . $hostname;

    $CONTACTS{'CONTACTEMAIL'}{'contact'} ||= [$root_email];

    return \%CONTACTS;
}

sub augment_contacts_with_default_levels {
    my ($contacts_ref) = @_;

    # Set defaults
    $contacts_ref->{'CONTACTEMAIL'}{'level'}      = $RECEIVES_NAME_TO_NUMBER{'All'};
    $contacts_ref->{'CONTACTPAGER'}{'level'}      = $RECEIVES_NAME_TO_NUMBER{'HighOnly'};
    $contacts_ref->{'CONTACTPUSHBULLET'}{'level'} = $RECEIVES_NAME_TO_NUMBER{'HighAndMediumOnly'};
    $contacts_ref->{'CONTACTUIN'}{'level'}        = $RECEIVES_NAME_TO_NUMBER{'HighAndMediumOnly'};

    Cpanel::iContact::Providers::augment_contacts_with_default_levels($contacts_ref);
    return 1;
}

sub _reset_contacts_cache {
    return %CONTACTS = ();
}

#This is a pretty "low-level" function that "normalizes" the attach_files
#parameter to icontact(). It's exposed publicly to facilitate wrappers
#around icontact().
#
#It expects either something false-y, or an arrayref.
#It die()s if "attach_files" is invalid.
#It returns an arrayref.
#
sub normalize_attach_files {
    my ($attach_files) = @_;

    $attach_files ||= [];

    if ( ref $attach_files ne 'ARRAY' ) {
        die "'attach_files', if given, must be an arrayref, not “$attach_files”!";
    }

    return $attach_files;
}

sub _save_notification_to_log {
    my (%OPTS) = @_;

    require Cpanel::iContact::History;

    my $log_user      = $OPTS{'log_user'};
    my $email_args_hr = $OPTS{'email_args_hr'};
    my $app           = $OPTS{'app'};
    my $RESERVED      = '';

    my $datastore_obj;

    if ( $log_user !~ /@/ ) {
        $datastore_obj = Cpanel::iContact::History::get_user_contact_history( 'user' => $log_user );
    }
    else {
        my ( $virtual_user, $domain ) = split( '@', $log_user, 2 );
        my $system_user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
        $datastore_obj = Cpanel::iContact::History::get_virtual_user_contact_history( 'user' => $system_user, 'virtual_user' => $virtual_user, 'domain' => $domain, 'service' => 'mail' );
    }

    $datastore_obj->purge_expired();

    my $filesys_safe_subject_header = $email_args_hr->{'subject'};
    $filesys_safe_subject_header =~ s{/}{_}g;
    $filesys_safe_subject_header =~ s{\0}{ }g;
    $filesys_safe_subject_header = substr( $filesys_safe_subject_header, 0, 200 );

    my $target = $datastore_obj->get_entry_target(
        'time'   => time(),
        'fields' => [ $app, $RESERVED, $RESERVED, $filesys_safe_subject_header ],
        'type'   => 'eml'
    );

    Cpanel::iContact::Email::write_email_to_fh( $target->{'fh'}, %{$email_args_hr} );

    return $target->{'path'};
}

1;
