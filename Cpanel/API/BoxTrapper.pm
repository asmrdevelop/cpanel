
# cpanel - Cpanel/API/BoxTrapper.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::BoxTrapper;

use strict;
use warnings;

use Cpanel::Imports;

use Cpanel::BoxTrapper          ();
use Cpanel::BoxTrapper::Actions ();
use Cpanel::Exception           ();
use Cpanel::Validate::Html      ();

=head1 MODULE

C<Cpanel::API::BoxTrapper>

=head1 DESCRIPTION

C<Cpanel::API::BoxTrapper> provides UAPI methods for querying and
managing the BoxTrapper application configuration and message queue.

=head1 FUNCTIONS

=head2 get_status(email => ...)

Gets the current status of BoxTrapper for the specific email account.

=head3 ARGUMENTS

=over

=item email - string

The email account you want the BoxTrapper status for. When called from WebMail, this parameter is ignored since a WebMail user can only adjust the settings on their own email account.

=back

=head3 RETURNS

Boolean - current status for the requested email account.

=over

=item When 1, BoxTrapper is enabled for the account.

=item When 0, BoxTrapper is disabled for the account.

=back

=head3 THROWS

=over

=item When the mail server role is not set for the server.

=item When the cPanel account does not have the 'boxtrapper' feature.

=item When the email account is not owned by the logged-in cPanel user.

=item When the configuration can not be read.

=back

=cut

sub get_status {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);

    my $status = Cpanel::BoxTrapper::BoxTrapper_isenabled(
        $email,
        { uapi => 1, validate => 1 },
    );

    $result->data($status);

    return 1;
}

=head2 set_status(email => ..., enabled => 0|1)

Sets the current status of BoxTrapper for the specific email account.

=head3 ARGUMENTS

=over

=item email - string

The email account you want to change the BoxTrapper status for. When called from WebMail, this parameter is ignored since a WebMail user can only adjust the setting on their own email account.

=item enabled - Boolean

=over

=item When 1, will enable BoxTrapper for the email account.

=item When 0, will disable BoxTrapper for the email account.

=back

=back

=head3 THROWS

=over

=item When the cPanel account is set to demo mode.

=item When the mail server role is not set for the server.

=item When the cPanel account does not have the 'boxtrapper' feature.

=item When the email account is not owned by the logged-in cPanel user.

=item When the configuration can not be saved.

=back

=cut

sub set_status {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);

    my $enabled = $args->get_length_required('enabled');    ## 1 | 0
    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die($enabled);

    Cpanel::BoxTrapper::BoxTrapper_changestatus(
        $email,
        $enabled ? 'enable' : 'disabled',
        { uapi => 1, validate => 1 }
    );

    return 1;
}

=head2 get_message(email => ..., queuefile => ...)

Retrieve up to the first 200 lines of a block email message from the queue.

=head3 ARGUMENTS

=over

=item email - string

The email account who owns the requested message. When called from WebMail, this parameter is ignored since a WebMail user can only adjust the setting on their own email account.

=item queuefile - string

Valid queuefile name. It may not contain an path traversal characters like: ./ ../ and must end with .msg. These should be treated like a unique id for a specific blocked message.

=back

=head3 RETURNS

=over

=item queuefile - string

Valid queuefile name. It may not contain an path traversal characters like: ./ ../ and must end with .msg. These should be treated like a unique id for a specific blocked message.

=item content - string

Up to the first 200 lines of the requested blocked email message.

=back

=head3 THROWS

=over

=item When the mail server role is not set for the server.

=item When the cPanel account does not have the 'boxtrapper' feature.

=item When the 'email' parameter is not passed or is empty.

=item When the 'queuefile' parameter is not passed or is empty.

=item When the email account is not owned by the logged in cPanel user.

=item When the requested message does not exist.

=item When the requested message contains path traversal characters such as .. or /.

=item When the requested message does not end in '.msg'.

=back

=cut

sub get_message {
    my ( $args, $result ) = @_;

    my $email     = _get_email_parameter($args);
    my $queuefile = $args->get_length_required('queuefile');
    _validate_queuefile($queuefile);

    my $content = Cpanel::BoxTrapper::get_message( $email, $queuefile, { uapi => 1, validate => 1 } ) || '';
    $result->data(
        {
            queuefile => $queuefile,
            content   => $content,
        }
    );

    return 1;
}

=head2 delete_messages()

Deletes a list of messages from the BoxTrapper queue.

=head3 ARGUMENTS

=over

=item email - string

The mailbox you want to process delete(s) for.

=item queuefile - string

One or more queuefiles to process. Each queue file must be in its own parameter instance.

=item all_like - Boolean

When present, all messages in the queue that are similar to the requested message will be deleted. Must be a 1 or 0.

=back

=head3 RETURNS

Array with hashes for each queuefile deleted where each hash has the following format:

=over

=item email - string

From email from the requested message that will be deleted.

=item operator - string

Will be 'delete' or 'deleteall' for this case.

=item matches - string[]

List of messages deleted based on the specific message.

=item failures - string[]

List of messages that could not be deleted due to failures.

=item failed - Boolean

If present, delete operation failed. See the 'reason' property for more information.

=item warning - Boolean

If present, there were non-critical problems processing the delete operation. See the 'reason' property for more information.

=item reason - string

May be present with details about the failure or warning.

=back

=head3 THROWS

=over

=item When no 'email' argument is passed.

=item When an empty 'email' argument is passed.

=item When no 'queuefile' argument is passed.

=item When an empty 'queuefile' argument is passed.

=item When an invalid 'queuefile' argument is passed.

=item When something other then a 1 or 0 is passed to the 'all_like' parameter.

=back

=cut

sub delete_messages {
    my ( $args, $result ) = @_;

    my $email      = _get_email_parameter($args);
    my @queuefiles = $args->get_multiple('queuefile');
    _validate_queuefile($_) foreach @queuefiles;
    _validate_one_or_more( 'queuefile', @queuefiles );

    my $all_like = $args->get('all_like') || 0;
    _validate_boolean($all_like);

    my $log = Cpanel::BoxTrapper::process_message_action(
        $email,
        \@queuefiles,
        [ $all_like ? 'deleteall' : 'delete' ],
        { uapi => 1, validate => 1 },
    );

    if ( my @has_errors = grep { $_->{failed} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the delete operations failed.') );
    }

    if ( my @has_warnings = grep { $_->{warning} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the delete operations has warnings.') );
    }

    $result->data($log);

    return 1;
}

=head2 ignore_messages()

Ignores a list of messages from the BoxTrapper queue.

=head3 ARGUMENTS

=over

=item email - string

The mailbox you want to ignore some messages for.

=item queuefile - string

One or more queuefiles to process. Each queue file must be in its own parameter instance.

=back

=head3 RETURNS

Array with hashes for each queuefile ignored where each hash has the following format:

=over

=item email - string

From email from the requested message that will be ignored.

=item operator - string

Will be 'ignore' for this case.

=item matches - string[]

List of messages that were used to add addresses to the ignored emails list.

=item failed - Boolean

If present, ignore operation failed. See the 'reason' property for more information.

=item warning - Boolean

If present, there were non-critical problems processing the ignore operation. See the 'reason' property for more information.

=item reason - string

May be present with details about the failure or warning.

=back

=head3 THROWS

=over

=item When no 'email' argument is passed.

=item When an empty 'email' argument is passed.

=item When no 'queuefile' argument is passed.

=item When an empty 'queuefile' argument is passed.

=item When an invalid 'queuefile' argument is passed.

=back

=cut

sub ignore_messages {
    my ( $args, $result ) = @_;

    my $email      = _get_email_parameter($args);
    my @queuefiles = $args->get_multiple('queuefile');
    _validate_queuefile($_) foreach @queuefiles;
    _validate_one_or_more( 'queuefile', @queuefiles );

    my $log = Cpanel::BoxTrapper::process_message_action(
        $email,
        \@queuefiles, [
            'ignore'
        ],
        { uapi => 1, validate => 1 }
    );

    if ( my @has_errors = grep { $_->{failed} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the ignore operations failed.') );
    }

    if ( my @has_warnings = grep { $_->{warning} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the ignore operations has warnings.') );
    }

    $result->data($log);

    return 1;
}

=head2 whitelist_messages()

Whitelists a list of messages from the BoxTrapper queue.

=head3 ARGUMENTS

=over

=item email - string

The mailbox you want to whitelist some messages for.

=item queuefile - string

One or more queuefiles to process. Each queue file must be in its own parameter instance.

=back

=head3 RETURNS

Array with hashes for each queuefile whitelisted where each hash has the following format:

=over

=item email - string

From email from the requested message that will be whitelisted.

=item operator - string

Will be 'whitelist' for this case.

=item matches - string[]

List of messages that were used to add new addresses to the whitelist.

=item failed  - Boolean

If present, whitelist operation failed. See the 'reason' property for more information.

=item warning - Boolean

If present, there were non-critical problems processing the whitelist operation. See the 'reason' property for more information.

=item reason - string

May be present with details about the failure or warning.

=back

=head3 THROWS

=over

=item When no 'email' argument is passed.

=item When an empty 'email' argument is passed.

=item When no 'queuefile' argument is passed.

=item When an empty 'queuefile' argument is passed.

=item When an invalid 'queuefile' argument is passed.

=back

=cut

sub whitelist_messages {
    my ( $args, $result ) = @_;

    my $email      = _get_email_parameter($args);
    my @queuefiles = $args->get_multiple('queuefile');
    _validate_queuefile($_) foreach @queuefiles;
    _validate_one_or_more( 'queuefile', @queuefiles );

    my $log = Cpanel::BoxTrapper::process_message_action(
        $email,
        \@queuefiles, [
            'whitelist'
        ],
        { uapi => 1, validate => 1 }
    );

    if ( my @has_errors = grep { $_->{failed} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the whitelist operations failed.') );
    }

    if ( my @has_warnings = grep { $_->{warning} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the whitelist operations has warnings.') );
    }

    $result->data($log);

    return 1;
}

=head2 deliver_messages()

Delivers a list of messages from the BoxTrapper queue.

=head3 ARGUMENTS

=over

=item email - string

The mailbox you want to process deliver actions for.

=item queuefile - string

One or more queuefiles to process. Each queue file must be in its own parameter instance.

=item all_like - Boolean

When present, all messages in the queue that are similar to the requested message will be delivered. Must be a 1 or 0.

=back

=head3 RETURNS

Array with hashes for each queuefile delivered where each hash has the following format:

=over

=item email - string

From email from the requested message that will be delivered.

=item operator - string

Will be 'deliver' or 'deliverall' for this case.

=item matches - string[]

List of messages delivered based on the specific message.

=item failures - hashref

With the following format:

=over

=item delivery - string[]

List of items that could not be delivered.

=item removal - string[]

List of items that were delivered, but failed to be removed from the queue.

=back

=item failed - Boolean

If present, deliver operation failed. See the 'reason' property for more information.

=item warning - Boolean

If present, there were non-critical problems processing the deliver operation. See the 'reason' property for more information.

=item reason - string

May be present with details about the failure or warning.

=back

=head3 THROWS

=over

=item When no 'email' argument is passed.

=item When an empty 'email' argument is passed.

=item When no 'queuefile' argument is passed.

=item When an empty 'queuefile' argument is passed.

=item When an invalid 'queuefile' argument is passed.

=item When something other then a 1 or 0 is passed to the 'all_like' parameter.

=back

=cut

sub deliver_messages {
    my ( $args, $result ) = @_;

    my $email      = _get_email_parameter($args);
    my @queuefiles = $args->get_multiple('queuefile');
    _validate_queuefile($_) foreach @queuefiles;
    _validate_one_or_more( 'queuefile', @queuefiles );

    my $all_like = $args->get('all_like') || 0;
    _validate_boolean($all_like);

    my $log = Cpanel::BoxTrapper::process_message_action(
        $email,
        \@queuefiles, [
            $all_like ? 'deliverall' : 'deliver'
        ],
        { uapi => 1, validate => 1 }
    );

    if ( my @has_errors = grep { $_->{failed} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the deliver operations failed.') );
    }

    if ( my @has_warnings = grep { $_->{warning} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the deliver operations has warnings.') );
    }

    $result->data($log);

    return 1;
}

=head2 blacklist_messages()

Blacklist a list of messages from the BoxTrapper queue.

=head3 ARGUMENTS

=over

=item email - string

The mailbox you want to blacklist some messages for.

=item queuefile - string

One or more queuefiles to process. Each queue file must be in its own parameter instance.

=back

=head3 RETURNS

Array with hashes for each queuefile blacklisted where each hash has the following format:

=over

=item email - string

From email from the requested message that will be blacklisted.

=item operator - string

Will be 'blacklist' for this case.

=item matches - string[]

List of messages that will be used to add addresses to the blacklist.

=item failed - Boolean

If present, the deliver operation failed. See the 'reason' property for more information.

=item warning - Boolean

If present, there were non-critical problems processing the deliver operation. See the 'reason' property for more information.

=item reason - string

May be present with details about the failure or warning.

=back

=head3 THROWS

=over

=item When no 'email' argument is passed.

=item When an empty 'email' argument is passed.

=item When no 'queuefile' argument is passed.

=item When an empty 'queuefile' argument is passed.

=item When an invalid 'queuefile' argument is passed.

=back

=cut

sub blacklist_messages {
    my ( $args, $result ) = @_;

    my $email      = _get_email_parameter($args);
    my @queuefiles = $args->get_multiple('queuefile');
    _validate_queuefile($_) foreach @queuefiles;
    _validate_one_or_more( 'queuefile', @queuefiles );

    my $log = Cpanel::BoxTrapper::process_message_action(
        $email,
        \@queuefiles, [
            'blacklist'
        ],
        { uapi => 1, validate => 1 }
    );

    if ( my @has_errors = grep { $_->{failed} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the blacklist operations failed.') );
    }

    if ( my @has_warnings = grep { $_->{warning} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the blacklist operations has warnings.') );
    }

    $result->data($log);

    return 1;
}

=head2 process_messages()

Processes a list of messages from the BoxTrapper queue. Each message is processed by the list of operators until one of the operators fails.

=head3 ARGUMENTS

=over

=item email - string[]

The mailbox you want to process some messages for.

=item action - string[]

One ore more actions to apply to the list of queuefile messages. Each action must be in its own parameter instance. Actions are limit to the following and are applied in the order they are listed in the arguments:

=over

=item * deliver

=item * deliverall

=item * delete

=item * deleteall

=item * blacklist

=item * whitelist

=item * ignore

=back

=item queuefile - string[]

One or more queuefiles to process. Each queue file must be in its own parameter instance.

=back

=head3 RETURNS

Array with hashes for each queuefile and action where each hash has the value described in the respective API documentation above:

=over

=item * L<deliver|/"deliver_messages()">

=item * L<deliverall|/"deliver_messages()">

=item * L<delete|/"delete_messages()">

=item * L<deleteall|/"delete_messages()">

=item * L<blacklist|/"blacklist_messages()">

=item * L<whitelist|/"whitelist_messages()">

=item * L<ignore|/"ignore_messages()">

=back

=head3 THROWS

=over

=item When no 'email' argument is passed.

=item When an empty 'email' argument is passed.

=item When no 'queuefile' argument is passed.

=item When an empty 'queuefile' argument is passed.

=item When an invalid 'queuefile' argument is passed.

=item When an empty 'action' argument is passed.

=item When an invalid 'action' argument is passed.

=back

=cut

sub process_messages {
    my ( $args, $result ) = @_;

    my $email      = _get_email_parameter($args);
    my @queuefiles = $args->get_multiple('queuefile');
    _validate_queuefile($_) foreach @queuefiles;
    _validate_one_or_more( 'queuefile', @queuefiles );

    my @actions = $args->get_multiple('action');
    _validate_actions( $email, @actions );
    _validate_one_or_more( 'action', @actions );

    my $log = Cpanel::BoxTrapper::process_message_action(
        $email,
        \@queuefiles,
        \@actions,
        { uapi => 1, validate => 1 }
    );

    if ( my @has_errors = grep { $_->{failed} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the operations failed.') );
    }

    if ( my @has_warnings = grep { $_->{warning} } @$log ) {
        $result->raw_warning( locale()->maketext('One or more of the operations has warnings.') );
    }

    $result->data($log);

    return 1;
}

=head2 _validate_queuefile(FILE) [PRIVATE]

Validates the format for a requested queued/blocked email filename.

=head3 ARGUMENTS

=over

=item FILE - string

Filename to check the formatting of.

=back

=head3 RETURNS

1 on success

=head3 THROWS

When the passed file has an invalid format or includes path traversal characters.

=cut

sub _validate_queuefile {
    my ($file) = @_;
    if ( $file !~ m/\.msg$/ || $file =~ m/[\.]{2,}|[\/]/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument is invalid.', ['queuefile'] );
    }
    return;
}

sub _validate_actions {
    my ( $email, @actions ) = @_;

    for my $action (@actions) {
        if ( !grep { $action eq $_ } @Cpanel::BoxTrapper::Actions::ALL_ACTIONS ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument with the value “[_2]” is not supported.', [ 'action', $action ] );
        }
    }
    return 1;
}

sub _validate_boolean {
    my ($candidate) = @_;
    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die($candidate);
    return;
}

sub _validate_one_or_more {
    my ( $name, @list ) = @_;
    if ( !@list ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be a list of one or more items.', [$name] );
    }
}

=head2 _get_email_parameter(ARGS) [PRIVATE]

Gets the email address to use with the API depending on what application is running: cPanel or Webmail.

=head3 ARGUMENTS

=over

=item ARGS - Cpanel::Args

API argument object.

=back

=head3 RETURNS

string - The email address to use.

=head3 THROWS

When the email address should be passed as an API argument but is missing or empty.

=cut

sub _get_email_parameter {
    my ($args) = @_;
    my $email = '';

    # For email webmail defaults to $Cpanel::authname in Cpanel::BoxTrapper
    if ( !$Cpanel::appname || $Cpanel::appname eq 'cpaneld' ) {
        $email = $args->get_length_required('email');
    }
    else {
        $email = $Cpanel::authuser;
    }

    Cpanel::Validate::Html::no_common_html_entities_or_die( $email, 'email' );

    return $email;
}

=head2 get_log(email => ..., date => ...)

=head3 ARGUMENTS

=over

=item email - string

The email account you want the BoxTrapper log for.

When called from cPanel, this parameter is required.

When called from WebMail, this parameter is ignored since a WebMail user can only query information for their own email account.

=item date - number

Optional. The linux epoch timestamp for the date of the log you want to retrieve. Defaults to the current date.

=back

=head3 RETURNS

A hash with the following properties:

=over

=item date - number

Linux timestamp representation of the date requested. This will be the same as the date argument passed in.

=item path - string

Path to the logfile for the date requests.

=item lines - string[]

The lines read from the log file. The lines have their trailing linefeeds stripped. The lines array is empty if the logfile does not exist or if there are no log lines in the file yet.

=back

=head3 THROWS

=over

=item When the mail server role is not set for the server.

=item When the cPanel account does not have the 'boxtrapper' feature.

=item When the email account is not owned by the logged-in cPanel user.

=item When the email account does not exist on the domain.

=item When an invalid date is passed.

=item When the log file can not be opened for some reason.

=item There may be other less common exceptions

=back

=cut

sub get_log {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);
    my $date  = $args->get('date');
    if ( defined $date ) {
        require Cpanel::Validate::Time;
        Cpanel::Validate::Time::epoch_or_die( $date, 'date' );
    }
    else {
        $date = time();
    }

    my $response = Cpanel::BoxTrapper::BoxTrapper_showlog(
        $date,
        $email,
        { uapi => 1, validate => 1 },
    ) || [];
    $result->data($response);

    return 1;
}

=head2 list_queued_messages(email => ... , date => ...)

List messages in queue, optionally for a specific date.

=head3 ARGUMENTS

=over

=item email - string

The email account you want the blocked messages for. When called from WebMail, this parameter is ignored since a WebMail user can only view their own email account.

=item date - integer

Optional UNIX timestamp for a specific date. If not provided it will default the the current day.

=back

=head3 NOTES

=over

=item * This UAPI call has optimized handling for filtering the 'from' or 'subject' fields if its the first filter.

=item * This UAPI call has optimized handling for filtering by the 'body' of a message when it is the first filter. If the 'body' filter is not the first filter the filter will fail since the body is not returned in the data set. Note, the 'body' field is never returned by this UAPI call.

=back

Array of block email where each item is a hashref with the following structure:

=over

=item from - string

Sender's email address(es) for the blocked email.

=item subject - string

Subject line for the blocked email.

=item queuefile - string

Unique id for the blocked message.

=item time - timestamp

Time the email was received.

=item error - string

If this property exists, something went wrong when reading the queued message.

=item When the email account is not owned by the logged-in cPanel user.

=item When a 'body' filter is requested after another filter.

=back

=head3 THROWS

=over

=item When the mail server role is not set for the server.

=item When the cPanel account does not have the 'boxtrapper' feature.

=item When the email account is not owned by the logged-in cPanel user.

=item When the email account does not exist on the domain.

=item When a 'body' filter is requested after another filter.

=item When an invalid date is passed.

=item When the log file can not be opened for some reason.

=item There may be other less common exceptions

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser BoxTrapper list_queued_messages email=maxwell@groovy.tld --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    "data" : [
        {
           "queuefile" : "rhzaBZzNQCaZ02EFqYblT-1557235836.msg",
           "subject" : "Go Gophers!!!",
           "from" : "gopher@groovy.tld",
           "time" : "1557235836"
        },
    ]

=head4 Command line usage for yesterday

    uapi --user=cpuser BoxTrapper list_queued_messages email=maxwell@groovy.tld date=$(date --date="1 days ago" +%s) --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    "data" : [
        {
           "queuefile" : "rhzaBZzNQCaZ02EFqYblT-1557172966.msg",
           "subject" : "Go Groundhogs!!!",
           "from" : "groundhog@groovy.tld",
           "time" : "1557172966"
        },
    ]

=head4 Command line usage filter by from field

    uapi --user=cpuser BoxTrapper list_queued_messages email=maxwell@groovy.tld api.filter_column=from api.filter_type=contains api.filter_term=groundhog --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    "data" : [
        {
           "queuefile" : "rhzaBZzNQCaZ02EFqYblT-1557172966.msg",
           "subject" : "Go Groundhogs!!!",
           "from" : "groundhog@groovy.tld",
           "time" : "1557172966"
        },
    ]

=head4 Command line usage filter by subject field

    uapi --user=cpuser BoxTrapper list_queued_messages email=maxwell@groovy.tld api.filter_column=subject api.filter_type=contains api.filter_term=gopher --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    "data" : [
        {
           "queuefile" : "rhzaBZzNQCaZ02EFqYblT-1557172966.msg",
           "subject" : "What are Gophers!!!",
           "from" : "groundhog@groovy.tld",
           "time" : "1557172966"
        },
    ]

=head4 Command line usage filter by body field

    uapi --user=cpuser BoxTrapper list_queued_messages email=maxwell@groovy.tld api.filter_column=body api.filter_type=contains api.filter_term=gopher --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    "data" : [
        {
           "queuefile" : "rhzaBZzNQCaZ02EFqYblT-1557172966.msg",
           "subject" : "Gophers are an animal!!!",
           "from" : "groundhog@groovy.tld",
           "time" : "1557172966"
        },
    ]

=head4 Template Toolkit

    [%
    SET result = execute('BoxTrapper', 'list_queued_messages', {
        email => 'maxwell@groovy.tld'
    });
    IF result.status;
        FOREACH item IN result.data %]
        <h3>[% item.subject %]</h3>
        <label>FROM:</label>
        [% item.from %]
        <label>DATE:</label>
        [% local.datetime(item.time, 'datetime_format_medium') %]
        [% END %]
    [% END %]

=cut

sub list_queued_messages {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);
    my $date  = $args->get('date');
    if ( defined $date ) {
        require Cpanel::Validate::Time;
        Cpanel::Validate::Time::epoch_or_die( $date, 'date' );
    }
    else {
        $date = time();
    }

    my $opts = {
        uapi     => 1,
        validate => 1,
        filters  => $args->filters(),
        sorts    => $args->sorts(),
    };

    my ( $messages, $count ) = Cpanel::BoxTrapper::list_queue(
        $date, $email,
        $opts,
    );

    $result->data($messages);

    return 1 if !$opts->{filters};

    for my $filter ( grep { $_->{handled} } @{ $opts->{filters} } ) {
        delete $filter->{handled};
        $result->mark_as_done($filter);
        $result->metadata( 'records_before_filter', $count );
    }

    return 1;
}

=head2 save_configuration(...)

Saves all the common BoxTrapper configuration properties for an account.

=head3 ARGUMENTS

=over

=item email - string

The email account you want the configuration applied to. When called from WebMail, this parameter is ignored since a WebMail user can only view their own email account.

=item from_addresses - string

Comma-separated list of email address to use in the from field for messages sent to the senders of blocked or ignored messages.

=item from_name - string

The personal name that the system uses in emails that it sends to blocked or ignored senders.
Note that only US ASCII characters, numbers, spaces, hyphens, or periods are currently supported.

=item queue_days - integer

The number of days that you wish to keep logs and messages in the queue. Must be positive number.

=item spam_score - number

Minimum Apache SpamAssassin Spam Score required to bypass BoxTrapper

=item enable_auto_whitelist - Boolean

When 1, when emails are sent from the email account, recipients in the To: and CC: fields are auto-whitelisted. When set to 0, no auto-whitelisting occurs.

=item whitelist_by_association - Boolean

Automatically whitelist the To and From lines from whitelisted senders

=back

=head3 THROWS

=over

=item When any of the following parameters are missing: email, from_addresses, queue_days, enable_auto_whitelist, from_name, whitelist_by_association.

=item When any of the following parameters are empty: email, from_addresses, queue_days, enable_auto_whitelist, whitelist_by_association.

=item When enable_auto_whitelist or whitelist_by_association are any value other then 0 or 1.

=item When email is not owned by the current cPanel account.

=item When the mailbox does not exist on the domain.

=item When the from_addresses field contains invalid email address or is not a properly formatted csv list.

=item When queue_days is not a positive integer.

=item When spam_score is not a valid decimal number.

=item When there are IO errors saving the configuration.

=item There may be other less common errors reported.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty BoxTrapper save_configuration email=one@domain.com from_addresses=me@domain.com from_name=Me queue_days=10 spam_score=1.5 enable_auto_whitelist=1 whitelist_by_association=1

=head4 Template Toolkit

    [%
    SET result = execute('BoxTrapper', 'save_configuration', {
        email                    => 'one@domain.com',
        from_addresses           => 'server@domain.com,help@domain.com',
        from_name                => "Digital Assistant",
        queue_days               => 30,
        spam_score               => 2.5,
        enable_auto_whitelist    => 1,
        whitelist_by_association => 1,
    });
    IF result.status %]
        Saved Configuration
    [% ELSE %]
        Failed to save with the following error(s): [% result.errors.join(', ') %]
    [% END %]
=cut

sub save_configuration {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);

    my $from_addresses  = $args->get_length_required('from_addresses');
    my $queue_days      = $args->get_length_required('queue_days');
    my $spam_score      = $args->get('spam_score');
    my $auto_whitelist  = $args->get_length_required('enable_auto_whitelist');
    my $from_name       = $args->get('from_name');
    my $whitelist_assoc = $args->get_length_required('whitelist_by_association');

    Cpanel::BoxTrapper::save_configuration(
        $email,
        {
            'from_addresses'        => $from_addresses,
            'queue_days'            => $queue_days,
            'enable_auto_whitelist' => $auto_whitelist,
            'whitelist_assoc'       => $whitelist_assoc,
            ( $args->exists('spam_score') ? ( 'spam_score' => $spam_score ) : () ),
            ( $args->exists('from_name')  ? ( 'from_name'  => $from_name )  : () ),
        }
    );

    return 1;
}

=head2 get_configuration()

Gets the BoxTrapper configuration settings for the requested email account.

=head3 ARGUMENTS

=over

=item email - string

The email account you want to retrieve the configuration for. When called from WebMail, this parameter is ignored since a WebMail user can only view their own email account.

=back

=head3 RETURNS

=over

=item from_addresses - string

Comma-separated list of email address to use in the from field for messages sent to the senders of blocked or ignored messages.

=item from_name - string

The personal name that the system uses in emails that it sends to blocked or ignored senders.

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

=item When the email parameter is missing.

=item When email is not owned by the current cPanel account.

=item When the mailbox for the email does not exist on the domain.

=item When there are IO errors loading the configuration.

=item There may be other less common errors reported.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty BoxTrapper get_configuration email=email@address.tld

The returned data will contain a structure similar to the JSON below:

    "data" : {
        "from_addresses": "one@domain.com,two@domain.com",
        "from_name": "The Machine Assistant",
        "queue_days": 15,
        "spam_score": -2.5,
        "enable_auto_whitelist": 1,
        "whitelist_by_association": 1
    }

=head4 Template Toolkit

    [%
    SET result = execute('BoxTrapper', 'get_configuration', {
        email => 'one@domain.com'
    });
    IF result.status;
        SET data = result.data
    %]
        From:                  [% data.from_addresses %]
        Name:                  [% data.from_name %]
        Retain (Days):         [% data.queue_days %]
        Minimum Spam Score:    [% data.spam_score %]
        Auto Whitelist:        [% IF data.enable_auto_whitelist%]True[%ELSE%]False[%END%]
        Include To, From & CC: [% IF data.whitelist_by_association%]True[%ELSE%]False[%END%]
    [% END %]

=cut

sub get_configuration {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);
    my $conf  = Cpanel::BoxTrapper::get_configuration($email);

    #translate keys from API1, since the old methods still rely on them
    my $response = {
        'from_addresses'           => $conf->{'froms'},
        'queue_days'               => $conf->{'stale-queue-time'},
        'spam_score'               => $conf->{'min_spam_score_deliver'},
        'enable_auto_whitelist'    => $conf->{'auto_whitelist'},
        'whitelist_by_association' => $conf->{'whitelist_by_assoc'},
        'from_name'                => $conf->{'fromname'}
    };
    $result->data($response);

    return 1;
}

=head2 list_email_templates()

Lists the default BoxTrapper message template types.

=head3 ARGUMENTS

No arguments

=head3 RETURNS

This api returns a list of the available message template types.

=head3 THROWS

=over

=item There may be errors reported from other parts of the system.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser BoxTrapper list_email_templates --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    ...
    "result" : {
      "messages" : null,
      "metadata" : {},
      "status" : 1,
      "data" : [
         "blacklist",
         "returnverify",
         "verifyreleased",
         "verify"
      ],
      "warnings" : null,
      "errors" : null
   }

=head4 Template Toolkit

    [% SET result = execute('BoxTrapper', 'list_email_templates');
    IF result.status;
    %]

        [% FOREACH message_type IN result.data %]
            <div>[% message_type %]</div>
        [% END %]

    [% END %]

=cut

sub list_email_templates {
    my ( $args, $result ) = @_;

    $result->data( [Cpanel::BoxTrapper::DEFAULT_TEMPLATES] );

    return 1;
}

=head2 get_email_template()

Gets the contents of a BoxTrapper message template.

=head3 ARGUMENTS

=over

=item email - string

The email account you want to retrieve the configuration for. When called from WebMail, this parameter is ignored since a WebMail user can only view their own email account.

=item template - string

One of blacklist, returnverify, verifyreleased, or verify

=back

=head3 RETURNS

This api returns the contents of the template file as a string.

=head3 THROWS

=over

=item When the email parameter is missing.

=item When the template parameter is missing.

=item When the template parameter is not a known template.

=item When email is not owned by the current cPanel account.

=item When the mailbox for the email does not exist on the domain.

=item When there are IO errors loading the template.

=item There may be other less common errors reported.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser BoxTrapper get_email_template email=email@domain.com template=blacklist --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    ...
    "result" : {
      "messages" : null,
      "metadata" : {},
      "status" : 1,
      "data" : "To: %email%\nSubject: Re: %subject%\n\nThe user %acct% does not accept mail from your address.\n\nThe headers of the message sent from your address are shown below:\n\n%headers%\n",
      "warnings" : null,
      "errors" : null
   }

=head4 Template Toolkit

    [% SET result = execute('BoxTrapper', 'get_email_template', {email => 'email@domain.com', template => 'blacklist'});
    IF result.status;
    %]

        <textarea>[% result.data %]</textarea>
        ...

    [% END %]

=cut

sub get_email_template {
    my ( $args, $result ) = @_;

    my $email    = _get_email_parameter($args);
    my $template = $args->get_length_required('template');

    $result->data( Cpanel::BoxTrapper::list_email_template( $email, $template ) );

    return 1;
}

=head2 save_email_template()

Sets the contents of a BoxTrapper message template.

=head3 ARGUMENTS

=over

=item email - string

The email account you want to retrieve the configuration for. When called from WebMail, this parameter is ignored since a WebMail user can only view their own email account.

=item template - string

One of:

=over

=item * blacklist

=item * returnverify

=item * verifyreleased

=item * verify

=back

=item contents - string

The complete text of the template UTF-8 encoded. You must include 'To: %email%' in this parameter's value.

If you use the verify template, you must include 'Subject: verify#%msgid%' in this parameter's value.

This parameter's value cannot exceed four kilobytes (KB).

=back

=head3 RETURNS

This api does not return data, only status.

=head3 THROWS

=over

=item When the email parameter is missing.

=item When the template parameter is missing.

=item When the template parameter is not a known template.

=item When email is not owned by the current cPanel account.

=item When the mailbox for the email does not exist on the domain.

=item When there are IO errors saving the template.

=item When the size of the template contents exceeds 4K.

=item When the size of the template contents is 0.

=item There may be other less common errors reported.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser BoxTrapper save_email_template email=email@domain.com template=blacklist     \
    contents="To: %email%\nSubject: Re: %subject%\n\nThe user %acct% does not accept mail from your address.\n\nThe headers of the message sent from your address are shown below:\n\n%headers%\n"     \
    --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    ...
    "result" : {
      "messages" : null,
      "metadata" : {},
      "status" : 1,
      "data" : null,
      "warnings" : null,
      "errors" : null
   }

=head4 Template Toolkit

    [% SET result = execute('BoxTrapper', 'save_email_template', {
        email => 'email@domain.com',
        template => 'blacklist',
        contents => "To: %email%\nSubject: Re: %subject%\n\nThe user %acct% does not accept mail from your address.\n\nThe headers of the message sent from your address are shown below:\n\n%headers%\n"
    });
    IF result.status;
    %]

        <h1>Success!</h1>
        ...
    [% ELSE %]
        [% FOREACH error in result.errors %]
            <p>[% error %]</p>
        [% END %]
    [% END %]

=cut

sub save_email_template {
    my ( $args, $result ) = @_;

    my $email    = _get_email_parameter($args);
    my $template = $args->get_length_required('template');
    my $contents = $args->get_length_required('contents');

    Cpanel::BoxTrapper::save_email_template( $email, $template, $contents );
    return 1;
}

=head2 reset_email_template()

Reset the contents of a BoxTrapper message template to the system default.

=head3 ARGUMENTS

=over

=item email - string

The email account you want to reset the template for. When called from WebMail, this parameter is ignored since a WebMail user can only view their own email account.

=item template - string

one of:

=over

=item * blacklist

=item * returnverify

=item * verifyreleased

=item * verify

=back

=back

=head3 RETURNS

This api returns only a status.

=head3 THROWS

=over

=item When the email parameter is missing.

=item When the template parameter is missing.

=item When the template parameter is not a known template.

=item When email is not owned by the current cPanel account.

=item When the mailbox for the email does not exist on the domain.

=item When there are IO errors loading the template.

=item There may be other less common errors reported.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser BoxTrapper reset_email_template email=email@domain.com template=blacklist --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    ...
    "result" : {
      "messages" : null,
      "metadata" : {},
      "status" : 1,
      "data" : null
      "warnings" : null,
      "errors" : null
   }

=head4 Template Toolkit

    [% SET result = execute('BoxTrapper', 'reset_email_template', {email => 'email@domain.com', template => 'blacklist'});
    IF result.status;
    %]

        <h1>Success!</h1>
        ...

    [% END %]

=cut

sub reset_email_template {
    my ( $args, $result ) = @_;

    my $email    = _get_email_parameter($args);
    my $template = $args->get_length_required('template');

    Cpanel::BoxTrapper::reset_email_template( $email, $template );

    return 1;
}

=head2 get_forwarders()

Gets the lines from the forwarders configuration file for the email account.

=head3 ARGUMENTS

=over

=item email - string

Email account to get the forwarders for.

=back

=head3 RETURNS

Arrayref of strings - list of forwarders.

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty BoxTrapper get_forwarders email=user@domain.com

The returned data will contain a structure similar to the JSON below:

    "data" : [
             "alternative@other.com",
             "support@website.net"
          ],

=head4 Template Toolkit

    [%
    SET result = execute('BoxTrapper', 'get_forwarders', {
        email => 'user@domain.com'
    });
    IF result.status;
        FOREACH pattern IN result.data %]
            [% pattern %]
    [%  END;
    END %]

=cut

sub get_forwarders {
    my ( $args, $result ) = @_;

    my $email = '';
    if ( !$Cpanel::appname || $Cpanel::appname eq 'cpaneld' ) {
        $email = $args->get_length_required('email');
    }

    $result->data( Cpanel::BoxTrapper::get_forwarders( $email, { uapi => 1, verification => 1 } ) );

    return 1;
}

=head2 set_forwarders

This method writes the complete forwarder file. If you are editing the forwarders, fetch the list
first from C<BoxTrapper::get_forwarders>. Edit that list and then convert it into C<forwarder> parameters.

=head3 ARGUMENTS

=over

=item email - string

The email account to set the forwarders for.

=item forwarder - string [ Support multiple ]

One or more lines to write to the forwarder file.

=back

=head3 THROWS

=over

=item When the MailReceive role is not supported on the server.

=item When the BoxTrapper feature is disabled for the user.

=item When the email account does not exist or is not owned by the cPanel user.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty BoxTrapper set_forwarders email=user@domain.com forwarder=other@domain.net

This method does not return any data in the data field.

=head4 Template Toolkit - add a new forwarder

    [%
    SET before = execute('BoxTrapper', 'get_forwarders', {
        email => 'user@domain.com'
    });

    IF before.status;

        SET result = execute('BoxTrapper', 'set_forwarders', {
            email => 'user@domain.com',
            forwarders => ['user2@domain', 'user3@domain']
        });
        IF result.status %]
        Updated the forwarders
        [% END %]
    [% END %]

=head4 Template Toolkit - to remove all forwarders

SET result = execute('BoxTrapper', 'set_forwarders', {
    email => 'user@domain.com',
});
IF result.status %]
All forwarders removed.
[% END %]

=cut

sub set_forwarders {
    my ( $args, $result ) = @_;

    my $email = '';
    if ( !$Cpanel::appname || $Cpanel::appname eq 'cpaneld' ) {
        $email = $args->get_length_required('email');
    }

    my @forwarders = $args->get_multiple('forwarder');

    my $ret = Cpanel::BoxTrapper::save_forwarders( $email, \@forwarders, { uapi => 1, verification => 1 } );
    return 1;
}

=head2 get_blocklist()

Gets the BoxTrapper blocklist for the requested email account. See API documentation for further information:

https://go.cpanel.net/boxtrapper-get_blocklist

=cut

sub get_blocklist {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);

    $result->data( Cpanel::BoxTrapper::get_blocklist( $email, { uapi => 1 } ) );

    return 1;
}

=head2 set_blocklist()

Sets the BoxTrapper blocklist for the requested email account. See API documentation for further information:

https://go.cpanel.net/boxtrapper-set_blocklist

=cut

sub set_blocklist {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);
    my @rules = $args->get_multiple('rules');
    _validate_one_or_more( 'rules', @rules );

    Cpanel::BoxTrapper::set_blocklist( $email, \@rules, { uapi => 1 } );
    return 1;
}

=head2 get_allowlist()

Gets the BoxTrapper allowlist for the requested email account. See API documentation for further information:

https://go.cpanel.net/boxtrapper-get_allowlist

=cut

sub get_allowlist {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);

    $result->data( Cpanel::BoxTrapper::get_allowlist( $email, { uapi => 1 } ) );

    return 1;
}

=head2 set_allowlist()

Sets the BoxTrapper allowlist for the requested email account. See API documentation for further information:

https://go.cpanel.net/boxtrapper-set_allowlist

=cut

sub set_allowlist {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);
    my @rules = $args->get_multiple('rules');
    _validate_one_or_more( 'rules', @rules );

    Cpanel::BoxTrapper::set_allowlist( $email, \@rules, { uapi => 1 } );
    return 1;
}

=head2 get_ignorelist()

Gets the BoxTrapper ignorelist for the requested email account. See API documentation for further information:

https://go.cpanel.net/BoxTrapper-get_ignorelist

=cut

sub get_ignorelist {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);

    $result->data( Cpanel::BoxTrapper::get_ignorelist( $email, { uapi => 1 } ) );

    return 1;
}

=head2 set_ignorelist()

Sets the BoxTrapper ignorelist for the requested email account. See API documentation for further information:

https://go.cpanel.net/boxtrapper-set_ignorelist

=cut

sub set_ignorelist {
    my ( $args, $result ) = @_;

    my $email = _get_email_parameter($args);
    my @rules = $args->get_multiple('rules');
    _validate_one_or_more( 'rules', @rules );

    Cpanel::BoxTrapper::set_ignorelist( $email, \@rules, { uapi => 1 } );
    return 1;
}

my $boxtrapper_mutating = {
    needs_role       => 'MailReceive',
    needs_feature    => 'boxtrapper',
    worker_node_type => 'Mail',
};

my $boxtrapper_non_mutating = {
    %$boxtrapper_mutating,
    allow_demo => 1,
};

our %API = (
    get_status           => $boxtrapper_non_mutating,
    set_status           => $boxtrapper_mutating,
    get_log              => $boxtrapper_non_mutating,
    list_queued_messages => $boxtrapper_non_mutating,
    get_configuration    => $boxtrapper_non_mutating,
    save_configuration   => $boxtrapper_mutating,
    get_message          => $boxtrapper_non_mutating,
    process_messages     => $boxtrapper_mutating,
    blacklist_messages   => $boxtrapper_mutating,
    deliver_messages     => $boxtrapper_mutating,
    whitelist_messages   => $boxtrapper_mutating,
    ignore_messages      => $boxtrapper_mutating,
    delete_messages      => $boxtrapper_mutating,
    get_email_template   => $boxtrapper_mutating,
    save_email_template  => $boxtrapper_mutating,
    reset_email_template => $boxtrapper_mutating,
    list_email_templates => $boxtrapper_non_mutating,
    get_forwarders       => $boxtrapper_non_mutating,
    set_forwarders       => $boxtrapper_mutating,
    get_blocklist        => $boxtrapper_non_mutating,
    set_blocklist        => $boxtrapper_mutating,
    get_allowlist        => $boxtrapper_non_mutating,
    set_allowlist        => $boxtrapper_mutating,
    get_ignorelist       => $boxtrapper_non_mutating,
    set_ignorelist       => $boxtrapper_mutating,
);

1;
