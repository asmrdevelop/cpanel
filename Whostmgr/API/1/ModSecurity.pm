
# cpanel - Whostmgr/API/1/ModSecurity.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::ModSecurity;

use strict;
use warnings;

use Cpanel::Exception                       ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();
use Cpanel::Hooks                           ();
use Cpanel::Locale 'lh';
use Cpanel::Logger                    ();
use Cpanel::Math                      ();
use Whostmgr::API::1::Utils           ();
use Whostmgr::ModSecurity::Vendor     ();
use Whostmgr::ModSecurity::VendorList ();

use constant NEEDS_ROLE => 'WebServer';

# Globals
my $logger;
our $locale;

=head1 NAME

Whostmgr::API::1::ModSecurity

=head1 TERMINOLOGY

'B<rule>' refers to a set of one or more mod_security directives, possibly including
descriptive comments, which go together as a single unit and share the same rule
id. For example, a chained set of B<SecRule> directives would be regarded as a
single rule, and an individual, non-chained B<SecRule> would also be a rule.

'B<setting>' refers to a mod_security configuration directive that is not a rule.
For example, the B<SecRuleEngine> directive is managed as a B<setting> rather than
as a B<rule>.

'B<chunk>' is sometimes used for a piece of rule or other directive text, in reference
to the way a configuration file is processed in chunks of text which may contain
multiple directives in some cases. (See Whostmgr::ModSecurity::Chunk for more.)

'B<id>' is the unique identification number of a rule. It is an attribute specific to
mod_security and is embedded in the action field. A rule id can be used to manipulate
existing rules through the API. Some functions in this API can only operate on
directives that have a rule id.

'B<config>' refers to a mod_security configuration file. The files are specified as
paths relative to the Apache configuration directory. You need to specify which
config you're dealing with when manipulating rules, because mod_security can have
multiple configuration files.

=head1 RULE CONFIGURATION

=head2 modsec_get_rules

=head3 Purpose

API handler that breaks a mod_security config file up into chunks of text grouped by
whether they belong together as a single unit (e.g., multiple chained rules need to
be treated as a single rule).

=head3 Arguments

    - 'config' | optional | The relative path to the mod_security config file we want to
        look at. For example, if 'foo/bar/myrules.conf' is specified, it will expand to:
        $apacheconf->dir_conf() . '/foo/bar/myrules.conf'. More than one config may be specified
        in the same field by passing a comma-delimited list, in which case the rules
        from all of those config files will be shown combined in the result set.
        This parameter may be omitted if 'vendor_id' is provided.
    - 'vendor_id' | optional | The vendor_id of the vendor whose rules you want to retrieve.
        For example, if 'MyVendor' is specified, and MyVendor has 10 config files, the
        effect would be the same as if you had requested all 10 of those config files.
        This paramater can also accept a comma-delimited list if you want more than one
        vendor's rules at the same time. This parameter may be omitted if 'config' is
        provided.
    - exclude_other_directives: (optional) (boolean) If set to 1, the returned chunks will only
        include SecRule and SecAction directives from the configuration file and comments not
        associated with a rule.
    - exclude_bare_comments: (optional) (boolean) If set to 1, the returned chunks will exclude
        comments that are not associated with any directive.

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_get_rules?api.version=1&config=example

=head3 Returns

The structure of this function's return value is identical to the return value of
the parse() function as documented in Whostmgr/ModSecurity/Parse.pm

  - 'chunks': The rules for the config file in question, split into meaningful chunks.
              Each chunk is a hash containing: 'id', 'rule', 'disabled', 'meta_msg',
              'staged', 'config', and 'vendor_id'.
              The 'chunks' array is the portion of the returned data eligible for
              sorting, filtering, and pagination.

  - 'staged_changes': A boolean, where 1 indicates that the data fine has staged changes

=cut

sub modsec_get_rules {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( @all_chunks, $staged_changes );

    my @vendors_to_examine = split( /,/, $args->{'vendor_id'} || '' );
    my @configs_to_examine = split( /,/, $args->{'config'}    || '' );

    if ( !@vendors_to_examine && !@configs_to_examine ) {
        die lh()->maketext(q{You must specify at least one [asis,vendor_id] or one configuration file.}) . "\n";
    }

    for (@vendors_to_examine) {
        my $v = Whostmgr::ModSecurity::Vendor->load( vendor_id => $_ );
        push @configs_to_examine, map { $_->{'config'} } @{ $v->configs };
    }

    require Whostmgr::ModSecurity::Parse;
    for my $config (@configs_to_examine) {
        my $config_file = Whostmgr::ModSecurity::get_safe_config_filename($config);
        my $parsed      = Whostmgr::ModSecurity::Parse::parse($config_file);
        if ($parsed) {
            if ( $args->{'exclude_other_directives'} || $args->{'exclude_bare_comments'} ) {
                my $exclude_other_directives = $args->{'exclude_other_directives'};
                my $exclude_bare_comments    = $args->{'exclude_bare_comments'};
                my @filteredChunks;
                foreach my $chunk ( @{ $parsed->{'chunks'} } ) {
                    if ( !$chunk->{'id'} ) {
                        my $is_comment = $chunk->{'rule'} =~ m/^#/;
                        if ( !( $exclude_other_directives && !$is_comment ) && !( $exclude_bare_comments && $is_comment ) ) {
                            push @filteredChunks, $chunk;
                        }
                    }
                    else {
                        # Since it has an id and a rule, its a SecAction or SecRule
                        push @filteredChunks, $chunk;
                    }
                }
                $parsed->{'chunks'} = \@filteredChunks;
            }
            push @all_chunks, @{ $parsed->{'chunks'} };
            $staged_changes ||= $parsed->{'staged_changes'};
        }
    }

    $metadata->{'result'}       = 1;
    $metadata->{'reason'}       = 'OK';
    $metadata->{'payload_name'} = 'chunks';    # hint for API 1 sorting, filtering, and pagination routines
    return { 'chunks' => \@all_chunks, 'staged_changes' => $staged_changes };
}

=head2 modsec_get_configs

=head3 Purpose

API handler that returns the list of known mod_security config files that currently exist.
This information can be used by the UI to give the option for toggling an entire config
file on or off (i.e. enabling or disabling its include).

=head3 Arguments

None

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_get_configs?api.version=1

=head3 Returns

    - 'configs': An array ref containing one hash ref per config file. The exact structure
                 returned for 'configs' is the return value of find() as specified in the
                 documentation for Whostmgr/ModSecurity/Find.pm

=cut

sub modsec_get_configs {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    require Whostmgr::ModSecurity::Find;
    my $config_files = Whostmgr::ModSecurity::Find::find();

    if ($config_files) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { configs => $config_files };
    }

    _initialize();
    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $locale->maketext('The system could not find any configuration files.');
    return;
}

=head2 modsec_disable_rule

=head3 Purpose

Disables a rule by id for the specified mod_security configuration file. This change will
be made in the staging copy of that configuration file, not directly in the file itself.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question.
  - 'id' - The id of the rule to be disabled

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_disable_rule?api.version=1&config=modsec_vendor_configs/example.conf&id=1234567

=head3 Returns

Nothing

=cut

sub modsec_disable_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $id ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_disable_rule" );

    require Whostmgr::ModSecurity::Configure;
    my $ok = eval { Whostmgr::ModSecurity::Configure::disable_rule( $config, $id ) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_disable_rule" );

        return {};
    }
}

=head2 modsec_undisable_rule

=head3 Purpose

Undisables a rule by id for the specified mod_security configuration file. This change will
be made in the staging copy of that configuration file, not directly in the file itself.

The term "undisable" (rather than "enable") is used to emphasize that a rule being disabled
is an abnormal condition created at the user's request, and undisabling is just restoring the
rule to its default state.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question.
  - 'id' - The id of the rule to be undisabled

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_undisable_rule?api.version=1&config=modsec_vendor_configs/example.conf&id=1234567

=head3 Returns

Nothing

=cut

sub modsec_undisable_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $id ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_undisable_rule" );

    require Whostmgr::ModSecurity::Configure;
    my $ok = eval { Whostmgr::ModSecurity::Configure::undisable_rule( $config, $id ) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_undisable_rule" );

        return {};
    }
}

=head2 modsec_get_configs_with_changes_pending

=head3 Purpose

This function looks for configuration files that have staged pending changes, and gives
back a list of those configs, which can be used in modsec_deploy_rule_changes.

=head3 Arguments

  - None

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_get_configs_with_changes_pending?api.version=1

=head3 Returns

    - 'configs': An array ref containing a list of config files.

=cut

sub modsec_get_configs_with_changes_pending {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    require Whostmgr::ModSecurity::Configure;
    my $configs_pending = Whostmgr::ModSecurity::Configure::get_configs_with_changes_pending();
    if ( scalar @$configs_pending > 0 ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { 'configs' => $configs_pending };
    }
    else {
        _initialize();
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('No rule changes are pending.');
        return {};
    }
}

=head2 modsec_deploy_rule_changes

=head3 Purpose

Assuming you already have changes staged for the config in question, this function deploys
those changes to the live copy, validates the changes, and restarts httpd. If the changes
are found to be invalid, httpd is not restarted, and a best effort is made to restore the
original configuration and restore your invalid changes to the staging copy.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_deploy_rule_changes?api.version=1&config=modsec_vendor_configs/example.conf

=head3 Returns

Nothing

=cut

sub modsec_deploy_rule_changes {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($config) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
    );

    _trigger_hook( "pre", "ModSecurity::modsec_deploy_rule_changes" );

    require Whostmgr::ModSecurity::Configure;
    my $ok = eval { Whostmgr::ModSecurity::Configure::deploy_rule_changes($config) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_deploy_rule_changes" );

        return {};
    }
}

=head2 modsec_deploy_all_rule_changes

=head3 Purpose

Like modsec_deploy_rule_changes, but deploys the changes for all configs with currently staged changes.

=head3 Arguments

n/a

=head3 Returns

  'outcomes': An array of hashes, each of which represents the outcome of one deploy
  operation and contains:
    - 'config': The config for which the deploy was attempted
    - 'ok': (Boolean) Whether the deploy succeeded
    - 'exception': (Only on failure) Why the deploy failed

  'failed': (Only on failure) An array of the names of the configs which could not be deployed.

=cut

sub modsec_deploy_all_rule_changes {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my $logger = Cpanel::Logger->new();

    my @outcomes;
    my @failed;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "pre", "ModSecurity::modsec_deploy_all_rule_changes" );

    require Whostmgr::ModSecurity::Configure;
    my $configs_pending = Whostmgr::ModSecurity::Configure::get_configs_with_changes_pending();
    for my $config (@$configs_pending) {
        my $ok        = eval { Whostmgr::ModSecurity::Configure::deploy_rule_changes($config) };
        my $exception = $@;
        if ( $exception || !$ok ) {
            push @outcomes, { 'config' => $config, ok => 0, 'exception' => $exception };
            $logger->warn( lh()->maketext( 'The system failed to deploy the changes for “[_1]”: [_2]', $config, Cpanel::Exception::get_string($exception) ) );
            push @failed, $config;
        }
        else {
            push @outcomes, { 'config' => $config, ok => 1 };
        }
    }

    if (@failed) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( q{The system could not deploy the configuration [numerate,_1,file,files] [list_and_quoted,_2]. Review the [asis,WHM error_log] file for more details about the error.}, scalar(@failed), \@failed );
        return { 'outcomes' => \@outcomes, 'failed' => \@failed };
    }

    _trigger_hook( "post", "ModSecurity::modsec_deploy_all_rule_changes" );

    return { 'outcomes' => \@outcomes };
}

=head2 modsec_discard_rule_changes

=head3 Purpose

Assuming you already have changes staged for the config in question, this function discards
those changes. Whatever was already in the live copy will be the basis for any future edits.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_discard_rule_changes?api.version=1&config=modsec_vendor_configs/example.conf

=head3 Returns

Nothing

=cut

sub modsec_discard_rule_changes {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($config) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
    );

    _trigger_hook( "pre", "ModSecurity::modsec_discard_rule_changes" );

    require Whostmgr::ModSecurity::Configure;
    require Whostmgr::ModSecurity::TransactionLog;
    my $ok = eval { Whostmgr::ModSecurity::Configure::discard_rule_changes($config) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        Whostmgr::ModSecurity::TransactionLog::log( operation => 'discard_rule_changes', arguments => { config => $args->{'config'} } );
        return {};
    }
}

=head2 modsec_discard_all_rule_changes

=head3 Purpose

Like modsec_discard_rule_changes, but discards the changes for all configs with currently staged changes.

=head3 Arguments

n/a

=head3 Returns

  'outcomes': An array of hashes, each of which represents the outcome of one discard
  operation and contains:
    - 'config': The config for which the discard was attempted
    - 'ok': (Boolean) Whether the discard succeeded
    - 'exception': (Only on failure) Why the discard failed

  'failed': (Only on failure) An array of the names of the configs for which the staged changes could not be discarded.

=cut

sub modsec_discard_all_rule_changes {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my @outcomes;
    my @failed;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "pre", "ModSecurity::modsec_discard_all_rule_changes" );

    require Whostmgr::ModSecurity::Configure;
    my $configs_pending = Whostmgr::ModSecurity::Configure::get_configs_with_changes_pending();
    for my $config (@$configs_pending) {
        my $ok        = eval { Whostmgr::ModSecurity::Configure::discard_rule_changes($config) };
        my $exception = $@;
        if ( $exception || !$ok ) {
            push @outcomes, { 'config' => $config, ok => 0, 'exception' => $exception };
            push @failed, $config;
        }
        else {
            push @outcomes, { 'config' => $config, ok => 1 };
        }
    }

    require Whostmgr::ModSecurity::TransactionLog;
    if (@failed) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = lh()->maketext( q{The system failed to discard the staged changes for the following configuration files: [list_and_quoted,_1]}, \@failed );
        return { 'outcomes' => \@outcomes, 'failed' => \@failed };
    }
    else {
        Whostmgr::ModSecurity::TransactionLog::log( operation => 'discard_all_rule_changes', arguments => {} );
    }

    _trigger_hook( "post", "ModSecurity::modsec_discard_all_rule_changes" );

    return { 'outcomes' => \@outcomes };
}

=head2 modsec_check_rule

=head3 Purpose

Checks whether a rule is valid.

=head3 Arguments

  - 'rule' - A string containing the text (can be multi-line) of the rule to be checked.

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_check_rule?api.version=1&rule=SecRule%20REQUEST_FILENAME%20%22example%22%20..........

=head3 Returns

  - 'valid': (BOOLEAN) Will be true if the rule was valid; otherwise false
  - 'problem': (STRING) (Only if invalid) This contains the description of what was invalid about the rule.

B<Important note>: An invalid rule is still considered a B<success> by modsec_check_rule, because even in
that case, the function successfully carried out its goal of determining whether the rule was valid or not.
A failure status will only be set if it was unable to determine whether the rule was valid.

=cut

sub modsec_check_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    _initialize();
    require Whostmgr::ModSecurity::Configure;
    my ( $valid, $statusmsg ) = eval { Whostmgr::ModSecurity::Configure::check_rule( $args->{'rule'} ) };
    if ($@) {    # This is an exception OTHER than the rule being invalid
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = $valid ? $locale->maketext('OK Valid Rule') : $locale->maketext('OK Invalid Rule');
        return {
            valid => $valid ? 1 : 0,
            !$valid ? ( problem => $statusmsg ) : ()
        };
    }
}

=head2 modsec_add_rule

=head3 Purpose

Adds a new rule to the specified config file.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)
  - 'rule' - A string containing the text (can be multi-line) of the rule to be added. If multiple
             directives belong to the same rule id, they should all be added via a single API
             query with a multi-line string.

You do not specify the id as an argument while adding a rule because the id is embedded in
the rule text.

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_add_rule?api.version=1&config=modsec_vendor_configs/example.conf&rule=SecRule%20REQUEST_FILENAME%20%22example%22%20..........

=head3 Returns

On success:

  - 'rule' - The parsed rule.

On failure:

  - 'duplicate' - (Only if a duplicate) This field will be present and true if the attempted queue item was a duplicate.

=cut

sub modsec_add_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $rule ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      rule
    );

    _trigger_hook( "pre", "ModSecurity::modsec_add_rule" );

    require Whostmgr::ModSecurity::Configure;
    my $new_rule = eval { Whostmgr::ModSecurity::Configure::add_rule( $config, $rule ) };
    if ( $@ || !$new_rule ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_add_rule" );

        return { rule => $new_rule };
    }
}

=head2 modsec_remove_rule

=head3 Purpose

Removes a rule from the specified config file.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)
  - 'id' - The id of the rule to remove

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_remove_rule?api.version=1&config=modsec_vendor_configs/example.conf&id=1234567

=head3 Returns

Nothing

=cut

sub modsec_remove_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $id ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_remove_rule" );

    require Whostmgr::ModSecurity::Configure;
    my $ok = eval { Whostmgr::ModSecurity::Configure::remove_rule( $config, $id ) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_remove_rule" );

        return {};
    }
}

=head2 modsec_edit_rule

=head3 Purpose

Edit an existing rule in a mod_security configuration file.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)
  - 'id'     - The rule id of the rule to edit. (Must already exist in the file)
  - 'rule'   - The new rule text to replace the existing rule text.


=head3 Returns

  - 'rule' - The parsed rule.

=cut

sub modsec_edit_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $id, $rule ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      id
      rule
    );

    _trigger_hook( "pre", "ModSecurity::modsec_edit_rule" );

    require Whostmgr::ModSecurity::Configure;
    my $ret_rule = eval { Whostmgr::ModSecurity::Configure::edit_rule( $config, $id, $rule ) };
    if ( $@ || !$ret_rule ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_edit_rule" );

        return { rule => $ret_rule };
    }
}

=head2 modsec_clone_rule

=head3 Purpose

Takes an existing rule and returns a copy of it (NOT saved anywhere) with a new rule ID that should
be valid for use in modsec2.user.conf. This is meant to be used in conjunction with a disable of the
original rule, allowing users to easily tweak vendor rules by disabling the original and then saving
a modified version into their modsec2.user.conf.

=head3 Arguments

  - 'config' - The ModSecurity configuration file containing the original rule.
  - 'id'     - the rule ID of the original rule.

=head3 Returns

  - 'rule' - The new rule information.

=cut

sub modsec_clone_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $id ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_clone_rule" );

    require Whostmgr::ModSecurity::Chunk::Get;
    my $rule = eval {
        my $chunk = Whostmgr::ModSecurity::Chunk::Get::get_chunk( $config, $id );

        $chunk->assign_new_unique_id();

        $chunk->plain;
    };
    if ( $@ || !$rule ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_clone_rule" );

        return { rule => $rule };
    }
}

=head2 modsec_report_rule

=head3 Purpose

Submits a report about a problem (false positive, false negative, warnings, etc.) for a ModSecurity rule
that was provided by a 3rd-party rule vendor. This report includes all of the information from the hits
table row from which the report was generated, along with other bits of information that may be useful
to the recipient when diagnosing the problem.

=head3 Arguments

  - 'row_ids':   - The MySQL row ID(s) from the hits table for the audit log event to report. This will be used
                   to look up additional details about the rule to be included in the report. If more than one
                   row ID is specified, they must be comma-separated, and they must all correspond to the same
                   ModSecurity rule id.
  - 'message':   - A short message (best entered by the user) explaining why the report is being submitted.
  - 'email':     - The email address of the person sending the report, so that a reply can be sent if needed.
  - 'type':      - The type of report being made. The possible contents of this field are not yet specified, and so it will be regarded as freeform text for the time being.
  - 'send':      - (boolean) If true, the report will actually be sent to the vendor. Otherwise, it will just
                   be generated and returned to the caller as a preview of what the report would look like.

=head3 Returns

  - 'report':    - The exact report that either was sent or would have been sent if 'send' were set.

=cut

sub modsec_report_rule {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    # Require the caller to be explicit about whether they want to send the report or not.
    if ( !exists $args->{send} ) {
        die lh()->maketext('You must specify a value for “[asis,send]” (0 or 1).') . "\n";
    }

    require Whostmgr::ModSecurity::Report;
    my $built_report = eval {
        my $report_obj = Whostmgr::ModSecurity::Report->new(
            row_ids => [ split /,/, $args->{row_ids} ],
            message => $args->{message},
            email   => $args->{email},
            type    => $args->{type},
        );

        if ( $args->{send} ) {
            $report_obj->send;
        }

        $report_obj->get;
    };
    if ($@) {
        return _handle_exception( $@, $metadata );
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { report => $built_report };
}

=head2 modsec_make_config_active

=head3 Purpose

Makes a configuration file active by adding an include for it.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_make_config_active?api.version=1&config=modsec_vendor_configs/example.conf

=head3 Returns

Nothing

=cut

sub modsec_make_config_active {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($config) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
    );

    _trigger_hook( "pre", "ModSecurity::modsec_make_config_active" );

    require Whostmgr::ModSecurity::Configure;
    my $ok = eval { Whostmgr::ModSecurity::Configure::make_config_active($config) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_make_config_active" );

        return {};
    }
}

=head2 modsec_make_config_inactive

=head3 Purpose

Makes the configuration file inactive by removing its include.

=head3 Arguments

  - 'config' - Relative path to the mod_security configuration file in question. (The live
               configuration file, not the staging copy.)

=head3 Example query

    /cpsessXXXXXXXXXX/json-api/modsec_make_config_inactive?api.version=1&config=modsec_vendor_configs/example.conf

=head3 Returns

Nothing

=cut

sub modsec_make_config_inactive {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($config) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
    );

    _trigger_hook( "pre", "ModSecurity::modsec_make_config_inactive" );

    require Whostmgr::ModSecurity::Configure;
    my $ok = eval { Whostmgr::ModSecurity::Configure::make_config_inactive($config) };
    if ( $@ || !$ok ) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        _trigger_hook( "post", "ModSecurity::modsec_make_config_inactive" );

        return {};
    }
}

=head2 modsec_get_config_text

=head3 Purpose

Returns the entire text of a mod_security configuration file. This may be used to inspect
the file or populate an editor view.

=head3 Arguments

  - 'config': The file
  - 'pagable' : Optional if provided and evaluate to true, the data is packaged as an array.
                If missing or false, the data is packages as a text blob.

=head3 Returns

  - 'text': The file's contents as a multi-line string

=cut

sub modsec_get_config_text {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($config) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
    );

    require Whostmgr::ModSecurity::Configure;
    my $text = Whostmgr::ModSecurity::Configure::get_config_text( $config, $args->{pagable} );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { text => $text };
}

=head2 modsec_set_config_text

=head3 Purpose

Set the entire contents of a mod_security configuration file. This may be used to
submit the results of a full text editor view.

=head3 Arguments

  - 'config': The file
  - 'text': The new contents of the file

=head3 Returns

n/a

=cut

sub modsec_set_config_text {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $text ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      text
    );

    _trigger_hook( "pre", "ModSecurity::modsec_set_config_text" );

    require Whostmgr::ModSecurity::Configure;
    eval { Whostmgr::ModSecurity::Configure::set_config_text( $config, $text ) };
    if ($@) {
        return _handle_exception( $@, $metadata );
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_set_config_text" );

    return {};
}

=head2 modsec_assemble_config_text

=head3 Purpose

Set the entire contents of a mod_security configuration file in a piecewise fashion.
This may be used to submit the results of a full text editor view in pieces across
multiple queries in order to allow for, e.g., a progress bar or other status indicator.

=head3 Arguments

  - 'config': The file
  - 'text': The contents of this piece of the file.
  - 'init': If true, indicates that this is the first piece being uploaded.
  - 'final': If true, indicates that this is the last piece being uploaded.
  - 'deploy': If true, also deploys the changes.

It's possible for either, both, or neither of 'init' and 'final' to be set.
However, the first upload must always have 'init' set, and the last must
always have 'final' set. If the first and last upload are the same, then
both should be set. In-between uploads should have neither set.

=head3 Returns

n/a

=cut

sub modsec_assemble_config_text {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ( $config, $text ) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      config
      text
    );

    _trigger_hook( "pre", "ModSecurity::modsec_assemble_config_text" );

    my $queue_flags = { init => $args->{init}, final => $args->{final} };
    require Whostmgr::ModSecurity::Configure;
    eval { Whostmgr::ModSecurity::Configure::assemble_config_text( $config, $text, $queue_flags, $args->{deploy} ) };
    if ($@) {
        return _handle_exception( $@, $metadata );
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_assemble_config_text" );

    return {};
}

=head1 MODSECURITY STATUS INFORMATION

=head2 modsec_get_log

=head3 Purpose

Get the list of mod_security rule hits.

=head3 Arguments

This function accepts the usual API 1 sorting and pagination parameters, which
are documented here:

https://go.cpanel.net/WHMAPI1

To experiment with sorting and pagination, see the API Shell feature in WHM.

=head3 Returns

=over

=item 'hits': An array of log events, each of which is a hash containing:

=over

=item 'action_desc': Notice sent to the the user when the hit occurred.

=item 'file_exists': Boolean - True if the file from meta_file exists; false otherwise.

=item 'handler': n/a

=item 'host': The Host header specified in the request.

=item 'http_method': The HTTP method. Examples: GET, POST, DELETE, PUT

=item 'http_status': The HTTP status code returned by the server for the request.

=item 'http_version': The HTTP version. Example: HTTP/1.1

=item 'id': The MySQL row id from the hits table. Not to be confused with B<meta_id>, which is the mod_security rule id.

=item 'ip': The client IP address from which the request originated.

=item 'justification': Technical details about the hit that may give some clues as to why the hit was generated.

=item 'meta_file': conf file where the rule lives.

=item 'meta_id': The mod_security rule id, if known. Not to be confused with B<id>, which is the MySQL row id.

=item 'meta_line': line in the conf file for the rule.

=item 'meta_logdata': The logdata field from the metadata.

=item 'meta_msg': Description for the rule triggering the hit.

=item 'meta_offset': The offset field from the metadata.

=item 'meta_rev': The rev field from the metadata.

=item 'meta_severity': one of: EMERGENCY, ALERT, CRITICAL, ERROR, WARNING, NOTICE, INFO and DEBUG.

=item 'meta_uri': The uri field from the metadata.

=item 'path': The path part of the request URI.

=item 'timestamp': The date in ISO-8601 format (YYYY-MM-DD HH:MM:SS) on which the log event occurred.

=item 'timezone': Offset from 0 (GMT) in minutes.

=back

=back

=cut

sub modsec_get_log {
    my ( $args, $metadata, $api_args ) = @_;

    require Whostmgr::ModSecurity::Log;
    my ( $log, $total_rows_in_table ) = Whostmgr::ModSecurity::Log::get_log( metadata => $metadata, api_args => $api_args );

    # Note: The use of the terms 'chunk'/'chunks' here in the metadata is part of the xml-api pagination
    # system. It should not be confused with 'chunk'/'chunks' used in some of the ModSecurity-related API
    # functions.

    my ( $start, $size ) = @{ $api_args->{chunk} }{qw(start size)};
    if ( $api_args->{chunk}{size} ) {
        $metadata->{chunk} = {
            start   => $start,
            size    => $size,
            records => $total_rows_in_table,
            chunks  => Cpanel::Math::ceil( $total_rows_in_table / $size ),
            current => Cpanel::Math::ceil( $start / $size ),
        };
    }

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    return { data => $log };
}

=head2 modsec_is_installed

=head3 Purpose

Tests if modsecurity is installed on Apache.

=head3 Arguments

None

=head3 Returns

=over

=item 'data': a hash containing:

=over

=item 'installed': 1 if installed, 0 if not installed.

=back

=back

=cut

sub modsec_is_installed {
    my ( $args, $metadata ) = @_;
    require Whostmgr::ModSecurity;
    my $installed = Whostmgr::ModSecurity::has_modsecurity_installed();
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { data => { installed => $installed } };
}

=head1 MODSECURITY GLOBAL SETTINGS

=head2 Overview of configurable settings

The following settings are configurable through this module:

  SecAuditEngine
  SecConnEngine
  SecDisableBackendCompression
  SecGeoLookupDb
  SecGsbLookupDb
  SecGuardianLog
  SecHttpBlKey
  SecPcreMatchLimit
  SecPcreMatchLimitRecursion
  SecRuleEngine

See the ModSecurity reference manual for more detailed information about each of these
configuration directives:

https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual

=head2 modsec_get_settings

=head3 Purpose

Returns the currently configured mod_security settings from the primary mod_security configuration file.
This only includes settings related to the overall behavior of mod_security and does not include any
rules. (For rule configuration, see modsec_get_configs and modsec_get_rules.)

=head3 Arguments

None

=head3 Returns

=over

=item 'settings': (ARRAY) An array of hashes, each of which represents a single ModSecurity global configuration setting.
(See "B<Format of a single setting>" below for the format of each setting)

=back

=head3 Format of a single setting

=over

=item 'setting_id': (INTEGER) A numeric id that may be used to identify this setting in set_setting API calls.
The correspondence of setting_id to actual setting is guaranteed to stay the same within a single version of the
product but may change across updates.

=item 'name': (STRING) The human-readable (and possibly localized) name for this setting, suitable for displaying in a table view.

=item 'description': (STRING) The human-readable (and possibly localized) description for this setting. This may be a single sentence or up to a couple paragraphs.

=item 'directive': (STRING) The Apache configuration directive to which this setting corresponds.

=item 'type': (STRING) The type of UI control this setting should use. See "B<Setting types>" near the end of this document
for details.

=item 'radio_options': (HASH) (Only for 'radio' type) If the setting is of type 'radio', this contains the structure
described below under "B<Structure of 'radio_options'>".

=item 'state': (STRING, or possibly other data) The current state of the setting. Currently, this will always be a string,
but it should be assumed that it could also contain complex data structures depending on the type of control being
represented.

=item 'url': (STRING) The URL to this setting's entry in the ModSecurity reference manual.

=item 'validation' : (ARRAY) Optional array of validation rules. Rules are run in the order they appear in this array.

=item 'default' : (ANY) Optional default value as defined by the modsec2 specification.

=item 'engine' : (BOOLEAN) Optional, if 1 means the rule is an engine directive, otherwise its just a normal directive. Engines have special handing in the UI.

=back

=head3 Structure of radio options

=over

=item 'name': (STRING) The human-readable (and possibly localized) short name for the radio option in question.

=item 'option': (STRING) The literal text contents of 'state' which should be sent back during set_setting if this radio option is selected.

=back

=head3 Structure of a validation rule

=over

=item (STRING) Name of the validation rule to run

=over

=item or

=back

=item (HASH) More complicated validation rule with the following:

=over

=item 'name' : (STRING) Name of the validation rule to run.

=item 'arg' : (STRING) Argument to the validation rule.

=back

=back


=cut

sub modsec_get_settings {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    require Whostmgr::ModSecurity::Settings;
    my $settings = eval { Whostmgr::ModSecurity::Settings::get_settings() };
    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
        return;
    }
    elsif ($settings) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { settings => $settings };
    }

    _initialize();
    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $locale->maketext('The system did not find any settings.');
    return;
}

=head2 modsec_set_setting

=head3 Purpose

Set the value of a single global ModSecurity configuration directive.

=head3 Arguments

=over

=item 'setting_id': (INTEGER) The numeric setting id for the setting in question, as returned
in the setting_id field by modsec_get_settings.

=item 'state': (STRING, or possibly other data) The new state to set for the setting in question.
Currently, this must always be a string, because there is not a mechanism for passing complex
data structures as API arguments, but this could change in the future depending on the
type of control being represented.

=back

=head3 Returns

'setting': The updated setting is returned in this field.

=cut

sub modsec_set_setting {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my $id    = $args->{'setting_id'};
    my $state = $args->{'state'};

    _trigger_hook( "pre", "ModSecurity::modsec_set_setting" );

    require Whostmgr::ModSecurity::Settings;
    eval { Whostmgr::ModSecurity::Settings::set_setting( $id, $state ); };
    if ($@) {
        return _handle_exception( $@, $metadata );
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }

    my $settings = Whostmgr::ModSecurity::Settings::get_settings();
    my ($setting) = grep { $_->{'setting_id'} == $id } @$settings;

    _trigger_hook( "post", "ModSecurity::modsec_set_setting" );

    return $setting;
}

=head2 modsec_remove_setting

=head3 Purpose

Remove a single global ModSecurity configuration directive.

=head3 Arguments

=over

=item 'setting_id': (INTEGER) The numeric setting id for the setting in question, as returned
in the setting_id field by modsec_get_settings.

=back

=head3 Returns

Nothing (but metadata is set to report success or failure)

=cut

sub modsec_remove_setting {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my $id = $args->{'setting_id'};

    _trigger_hook( "pre", "ModSecurity::modsec_remove_setting" );

    require Whostmgr::ModSecurity::Settings;
    eval { Whostmgr::ModSecurity::Settings::remove_setting($id) };
    if ($@) {
        return _handle_exception( $@, $metadata );
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_remove_setting" );

    return {};
}

=head2 modsec_batch_settings

=head3 Purpose

Process a set of global ModSecurity configuration directives, adding, updating or removing them
as instructed.

=head3 Arguments

=over

=item 'setting_id#': (INTEGER) The numeric setting id for the setting in question, as returned
in the setting_id field by modsec_get_settings.

=item 'state#': (STRING, or possibly other data) The new state to set for the setting in question.
Currently, this must always be a string, because there is not a mechanism for passing complex
data structures as API arguments, but this could change in the future depending on the
type of control being represented.

=item 'remove#': (BOOLEAN) If true, will remove the specified setting, if false or absent the directive
is added or updated depending on its current presence in the config file..

=back

=head3 Returns

'updated_settings': A list of the updated settings just as modsec_get_settings would.

=cut

sub modsec_batch_settings {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    _initialize();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "pre", "ModSecurity::modsec_batch_settings" );

    require Whostmgr::ModSecurity::Settings;
    my @keys     = keys %{$args};
    my @failures = ();
    foreach my $key (@keys) {
        if ( $key =~ m/setting_id(\d+)$/ ) {
            my $ct = $1;

            my $id     = $args->{"setting_id$ct"};
            my $state  = $args->{"state$ct"};
            my $remove = $args->{"remove$ct"};

            if ($remove) {
                eval { Whostmgr::ModSecurity::Settings::remove_setting($id); };
                push @failures, { "setting_id$ct" => $id, "remove$ct" => 1, "error$ct" => $@ } if $@;
            }
            else {
                eval { Whostmgr::ModSecurity::Settings::set_setting( $args->{"setting_id$ct"}, $args->{"state$ct"} ); };
                push @failures, { "setting_id$ct" => $id, "state$ct" => $state, "error$ct" => $@ } if $@;
            }
        }
    }

    if ( scalar @failures > 0 ) {
        my %failure_hash;
        foreach my $fail (@failures) {
            my @error_key    = grep { /^error/ } keys %$fail;
            my $fail_message = $fail->{ $error_key[0] };
            $fail_message =~ s/^\s+|\s+$//g;
            $failure_hash{$fail_message} = 1;
        }
        my @unique_failures = keys %failure_hash;

        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext(
            'The system could not save some of the settings for the following reason(s): [list_and_quoted,_1]',
            \@unique_failures
        );

        # some of these settings could have succeeded
        _trigger_hook( "post", "ModSecurity::modsec_batch_settings" );

        return { failures => \@failures };
    }

    if ( $args->{commit} ) {
        eval { Whostmgr::ModSecurity::Settings::deploy_settings_changes() };
        if ( my $exception = $@ ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext( 'The system could not deploy your configuration changes due to the following error: [_1]', $exception );
        }
    }

    return {} if !$metadata->{'result'};

    my $all_settings = Whostmgr::ModSecurity::Settings::get_settings();
    my @updated_settings;
    foreach my $key (@keys) {
        if ( $key =~ m/setting_id(\d+)/ ) {
            my $ct        = $1;
            my $id        = $args->{"setting_id$ct"};
            my ($setting) = grep { $_->{'setting_id'} == $id } @$all_settings;
            push @updated_settings, $setting;
        }
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_batch_settings" );

    return { updated_settings => \@updated_settings };
}

=head2 modsec_deploy_settings_changes

=head3 Purpose

Assuming you have already staged setting changes using modsec_set_setting, this function
deploys them to the live copy of modsec2.conf and attempts to restart Apache. If the new
settings fail validation in any way, the original modsec2.conf is restored.

This function is analogous to modsec_deploy_rule_changes and is currently implemented
as a wrapper around that function.

=head3 Arguments

None

=head3 Returns

This function does not return any data, but it will set the metadata according to whether
it succeeded or failed.

=cut

sub modsec_deploy_settings_changes {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    _trigger_hook( "pre", "ModSecurity::modsec_deploy_settings_changes" );

    require Whostmgr::ModSecurity::Settings;
    Whostmgr::ModSecurity::Settings::deploy_settings_changes();
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_deploy_settings_changes" );

    return {};
}

=head2 Setting types

=head3 text

A setting for a directive that takes a single string as its argument which
is best freeform edited by the user rather than constrainted to a set of options.

=head3 radio

A setting for a directive which takes a certain set of possible values
for its argument, and which is best presented as a set of radio buttons.

This setting type may also be used for boolean values that would sometimes
be presented as a checkbox.

=head1 MODSECURITY VENDORS

=head2 modsec_get_vendors

=head3 Purpose

Get a list of currently-installed ModSecurity vendors.

=head3 Arguments

'show_uninstalled': (Optional boolean) If specified, the result set will also include any vendors
which are not installed but available. This may be used for offering users the option of installing
the vendor in question. Note that the records for these available vendors are a subset of the regular
vendor records, so callers must be able to handle incomplete data if B<show_uninstalled> is used.

=head3 Returns

B<Important note>: Vendor attributes are omitted if they are empty, which is especially likely to be
true for uninstalled vendors that still appear in the list, so callers of vendor-related functions
need to check for the existence of vendor attributes before attempting to use them.

 'vendors': (array of hashes)
    'archive_url': The URL to download the rules for this vendor, based on the current version of
                   ModSecurity that is installed.
    'configs': (array of hashes)
        'active': (boolean) If true, the config is active
        'config': The relative path to the configuration file from the Apache configuration prefix
        'vendor_id': The short unique name of the vendor to which this config belongs.
    'cpanel_provided': (boolean) If true, this rule set is distributed (but not authored) by cPanel, L.L.C.
                       It may still be deleted if installed.
    'description': A brief description of the vendor and/or its rules. May be as short as one sentence or
                   up to multiple paragraphs long, and clients should accommodate any length of text.
    'dist_md5': The expected md5 of the file specified in archive_url.
    'enabled': (boolean) If true, the vendor is enabled. This doesn't necessarily mean that its rules
               are in effect, which depends on other settings too, just that the vendor as a whole is
               enabled.
    'in_use': (boolean) If true, at least one of the vendor's configs is active.
    'inst_dist': (only if the vendor is installed) The name of the distribution that was installed. This
                 attribute is used for determining whether an update is required.
    'installed': (boolean) If true, the vendor is installed. In most cases, a vendor will simply not appear
                 in the list if it is not installed, so the only case where this should ever be false is
                 if the caller is being given the chance to install it using pre-filled information.
    'installed_from': The URL to the YAML file from which the vendor either was installed or could be installed.
    'name': The short human-readable name of the vendor. Should be no more than several words long.
    'path': The path to this vendor's directory under the Apache configuration directory.
    'vendor_id': The short unique name of the vendor, used for identifying it in API calls.
    'vendor_url': A URL to the vendor's web site. May be used for presenting a "more information" type link
                  to the user.
    'report_url': The URL to a Report Receiver API endpoint provided by the vendor. This may be used in
                  conjunction with the Report Rule feature in WHM (or a modsec_report_rule API call) to
                  report problems with the rule.

=cut

sub modsec_get_vendors {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my $vendors =
      $args->{'show_uninstalled'}
      ? Whostmgr::ModSecurity::VendorList::list_detail_and_provided()
      : Whostmgr::ModSecurity::VendorList::list_detail();

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';
    return { vendors => $vendors };
}

=head2 modsec_add_vendor

=head3 Purpose

Install a vendor rule set on the server.

=head3 Arguments

  'url': A URL to the YAML metadata describing the vendor and how to obtain its rules.
  'enabled': (optional boolean) Whether to also enable the vendor on add. (Not its individual configs, though)

=head3 Returns

B<Important note>: Vendor attributes are omitted if they are empty, which is especially likely to be
true for uninstalled vendors that still appear in the list, so callers of vendor-related functions
need to check for the existence of vendor attributes before attempting to use them.

Additional note: The response from modsec_add_vendor is an abridged version of the response from
modsec_get_vendors. (The 'configs' array is not included.)

  'archive_url': The URL to download the rules for this vendor, based on the current version of
                 ModSecurity that is installed.
  'cpanel_provided': (boolean) If true, this rule set is distributed (but not authored) by cPanel, L.L.C.
                     It may still be deleted if installed.
  'description': A brief description of the vendor and/or its rules. May be as short as one sentence or
                 up to multiple paragraphs long, and clients should accommodate any length of text.
  'dist_md5': The expected md5 of the file specified in archive_url.
  'enabled': (boolean) If true, the vendor is enabled. This doesn't necessarily mean that its rules
             are in effect, which depends on other settings too, just that the vendor as a whole is
             enabled.
  'inst_dist': (only if the vendor is installed) The name of the distribution that was installed. This
               attribute is used for determining whether an update is required.
  'installed': (boolean) If true, the vendor is installed. In most cases, a vendor will simply not appear
               in the list if it is not installed, so the only case where this should ever be false is
               if the caller is being given the chance to install it using pre-filled information.
  'installed_from': The URL to the YAML file from which the vendor either was installed or could be installed.
  'name': The short human-readable name of the vendor. Should be no more than several words long.
  'path': The path to this vendor's directory under the Apache configuration directory.
  'vendor_id': The short unique name of the vendor, used for identifying it in API calls.
  'vendor_url': A URL to the vendor's web site. May be used for presenting a "more information" type link
                to the user.
  'report_url': The URL to a Report Receiver API endpoint provided by the vendor. This may be used in
                conjunction with the Report Rule feature in WHM (or a modsec_report_rule API call) to
                report problems with the rule.

=head3 Query examples

/json-api/modsec_add_vendor?api.version=1&url=http%3A%2F%2Fexample.invalid%2Fmeta_OWASP.yaml

/xml-api/modsec_add_vendor?api.version=1&url=http%3A%2F%2Fexample.invalid%2Fmeta_OWASP.yaml

=cut

sub modsec_add_vendor {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my $added_vendor = Whostmgr::ModSecurity::VendorList::add( $args->{url} );

    _trigger_hook( "pre", "ModSecurity::modsec_add_vendor" );

    if ( $args->{enabled} ) {
        Whostmgr::ModSecurity::ModsecCpanelConf->new->enable_vendor( $added_vendor->vendor_id );
    }

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_add_vendor" );

    return $added_vendor->export_fresh();
}

=head2 modsec_update_vendor

=head3 Purpose

Updates an already-installed vendor to version available at the specified URL.

=head3 Arguments

'url': The URL to the vendor metadata YAML file. Must be of form http://<hostname>/meta_<vendor_id>.yaml

=head3 Returns

  'vendor': (hash) A data structure representing the updated vendor, of the same form returned by modsec_add_vendor.

  'diagnostics': (hash) Diagnostic information about the difference between the old version and the new version of the vendor rule set.
      'added_configs': (array) List of configs that are added in the vendor update
      'deleted_configs': (array) List of configs that are removed in the vendor update
      'new_configs': (array) Complete list of configs in the update
          'active': (boolean) Whether the config in question is active
          'config': (string) The relative path to the config from the Apache configuration prefix
          'vendor_id': (string) The vendor_id to which the config belongs. (Should alwys match the vendor_id being updated)
      'prev_configs': (hash) Complete list of configs in the old version.
          'config': (string) The relative path to the config from the Apache configuration prefix

=cut

sub modsec_update_vendor {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    _trigger_hook( "pre", "ModSecurity::modsec_update_vendor" );

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    my $ret = Whostmgr::ModSecurity::VendorList::update( $args->{url} );

    _trigger_hook( "post", "ModSecurity::modsec_update_vendor" );

    return $ret;
}

=head2 modsec_remove_vendor

=head3 Purpose

Uninstall a set of vendor configs for ModSecurity.

The following steps are performed:

  1. Uninclude all of the vendor's config files.
  2. Clean up any leftover disablements for this vendor's rules.
  3. Delete the vendor's config files.
  4. Delete the vendor metadata file.

=head3 Arguments

  'vendor_id': The short unique name of the vendor

=head3 Returns

n/a

=head3 Example queries

/json-api/modsec_remove_vendor?api.version=1&vendor_id=SomeVendor

/xml-api/modsec_remove_vendor?api.version=1&vendor_id=SomeVendor

=cut

sub modsec_remove_vendor {
    my ( $args, $metadata ) = @_;

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _require_modsecurity_installed();

    _trigger_hook( "pre", "ModSecurity::modsec_remove_vendor" );

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
    $vendor->uninstall();

    _trigger_hook( "post", "ModSecurity::modsec_remove_vendor" );

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';
    return {};
}

=head2 modsec_preview_vendor

=head3 Purpose

Preview the metadata of a vendor rule set without actually installing it on the server.

=head3 Arguments

  'url': A URL to the YAML metadata describing the vendor and how to obtain its rules.

=head3 Returns

This function returns a data structure in the same format returned by modsec_add_vendor.
The only difference is that it doesn't actually perform the add operation.

=cut

sub modsec_preview_vendor {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';
    return Whostmgr::ModSecurity::VendorList::preview( $args->{url} );
}

=head2 modsec_enable_vendor_configs

=head3 Purpose

Iteratively attempt to enable all configuration files belonging to the vendor in question.
If any fail to validate, skip them and move on.

=head3 Arguments

  'vendor_id': The short unique identifier of the vendor

=head3 Returns

  'outcomes': An array containing elements representing the outcome of each attempted
              enable operation.

              Each element is a hash containing:

                  'active': (boolean) True if the config is active; false otherwise
                  'config': Relative path to the configuration file in question
                  'exception': (only on failure) The exception string representing the validation failure that occurred
                  'ok': (boolean) True if the operation succeeded; false otherwise

=head3 Examples

/json-api/modsec_enable_vendor_configs?api.version=1&vendor_id=SomeVendor

/xml-api/modsec_enable_vendor_configs?api.version=1&vendor_id=SomeVendor

=cut

sub modsec_enable_vendor_configs {
    my ( $args, $metadata ) = @_;

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _require_modsecurity_installed();

    _trigger_hook( "pre", "ModSecurity::modsec_enable_vendor_configs" );

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
    my ( $status, $outcomes ) = $vendor->enable_configs;
    $metadata->{result} = $status;
    $metadata->{reason} = $status ? 'OK' : 'Problem';

    my %active = map { $_->{config} => $_->{active} } @{ $vendor->configs };
    for (@$outcomes) {
        $_->{active} = $active{ $_->{config} };
    }

    _trigger_hook( "post", "ModSecurity::modsec_enable_vendor_configs" );

    return { outcomes => $outcomes };
}

=head2 modsec_disable_vendor_configs

=head3 Purpose

Iteratively attempt to disable all configuration files belonging to the vendor in question.
If any fail to validate, skip them and move on.

=head3 Arguments

  'vendor_id': The short unique identifier of the vendor

=head3 Returns

  'outcomes': An array containing elements representing the outcome of each attempted
              disable operation.

              Each element is a hash containing:

                  'active': (boolean) True if the config is active; false otherwise
                  'config': Relative path to the configuration file in question
                  'exception': (only on failure) The exception string representing the validation failure that occurred
                  'ok': (boolean) True if the operation succeeded; false otherwise

=head3 Examples

/json-api/modsec_disable_vendor_configs?api.version=1&vendor_id=SomeVendor

/xml-api/modsec_disable_vendor_configs?api.version=1&vendor_id=SomeVendor

=cut

sub modsec_disable_vendor_configs {
    my ( $args, $metadata ) = @_;

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _require_modsecurity_installed();

    _trigger_hook( "pre", "ModSecurity::modsec_disable_vendor_configs" );

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
    my ( $status, $outcomes ) = $vendor->disable_configs;
    $metadata->{result} = $status;
    $metadata->{reason} = $status ? 'OK' : 'Problem';

    my %active = map { $_->{config} => $_->{active} } @{ $vendor->configs };
    for (@$outcomes) {
        $_->{active} = $active{ $_->{config} };
    }

    _trigger_hook( "post", "ModSecurity::modsec_disable_vendor_configs" );

    return { outcomes => $outcomes };
}

=head2 modsec_enable_vendor

=head3 Purpose

Flag a vendor as being enabled overall, meaning its configs are eligible for including,
whether they are themselves enabled or not.

Important note: Enabling a vendor does not in and of itself guarantee that its config
files become enabled. (Config enable/disable is managed separately.) It is merely a
prerequisite.

=head3 Arguments

  'vendor_id': The short unique name of the vendor

=head3 Returns

n/a

=head3 Example queries

/json-api/modsec_enable_vendor?api.version=1&vendor_id=SomeVendor

/xml-api/modsec_enable_vendor?api.version=1&vendor_id=SomeVendor

=cut

sub modsec_enable_vendor {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_enable_vendor" );

    Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id )->enable();

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_enable_vendor" );

    return {};
}

=head2 modsec_disable_vendor

=head3 Purpose

Flag a vendor as being disabled overall, meaning its configs are not eligible for including.

Important note: Although disabling a vendor does remove the includes for all of its configs,
it does not individually flag those configs as disabled. Therefore, when a vendor is re-enabled,
the enabled/disabled states of its individual configs as they existed beforehand will be preserved.

=head3 Arguments

  'vendor_id': The short unique name of the vendor

=head3 Returns

n/a

=head3 Example queries

/json-api/modsec_disable_vendor?api.version=1&vendor_id=SomeVendor

/xml-api/modsec_disable_vendor?api.version=1&vendor_id=SomeVendor

=cut

sub modsec_disable_vendor {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_disable_vendor" );

    Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id )->disable();

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_disable_vendor" );

    return {};
}

=head2 modsec_enable_vendor_updates

=head3 Purpose

Enables automatic updates for the vendor in question. New copies of the vendor metadata will
be regularly pulled down from the same URL you used during the initial install of the vendor,
and if any updates are available, the new version of the rule set will be fetched and installed.

=head3 Arguments

  'vendor_id': The short unique name of the vendor

=head3 Returns

n/a

=cut

sub modsec_enable_vendor_updates {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_enable_vendor_updates" );

    Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id )->enable_updates();

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_enable_vendor_updates" );

    return {};
}

=head2 modsec_disable_vendor_updates

=head3 Purpose

Disables automatic updates for the vendor in question.

=head3 Arguments

  'vendor_id': The short unique name of the vendor

=head3 Returns

n/a

=cut

sub modsec_disable_vendor_updates {
    my ( $args, $metadata ) = @_;

    _require_modsecurity_installed();

    my ($vendor_id) = map { Whostmgr::API::1::Utils::get_required_argument( $args, $_ ) } qw(
      vendor_id
    );

    _trigger_hook( "pre", "ModSecurity::modsec_disable_vendor_updates" );

    Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id )->disable_updates();

    $metadata->{result} = 1;
    $metadata->{reason} = 'OK';

    _trigger_hook( "post", "ModSecurity::modsec_disable_vendor_updates" );

    return {};
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _initialize
# Desc:
#   initialize the logger and local system if they are not already initialized.
# Arguments:
#   N/A
# Returns:
#   N/A
#-------------------------------------------------------------------------------------------------
sub _initialize {
    $logger ||= Cpanel::Logger->new();
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private
# Name:
#   _handle_exception
# Desc:
#   Convert an exception from one of the ModSecurity-related functions into something
#   that can be returned back through the API. Specifically, handles the case of converting
#   a DuplicateQueueItem exception into a flag for the API caller to check rather than just
#   an string.
# Arguments:
#   - The exception (whether string or object)
#   - The metadata (to be updated by this function)
# Returns:
#   - The data for the caller to return (if any)
#-------------------------------------------------------------------------------------------------
sub _handle_exception {
    my ( $exception, $metadata ) = @_;
    _initialize();

    if ( ref $exception eq 'Cpanel::Exception::ModSecurity::DuplicateQueueItem' ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $exception->get_string;
        return { duplicate => 1 };
    }
    elsif ( ref $exception && eval { $exception->isa('Cpanel::Exception') } ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $exception->get_string;
        return;
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $exception || $locale->maketext('An unknown error occurred.');
    return;
}

sub _require_modsecurity_installed {
    return 1 if Whostmgr::ModSecurity::has_modsecurity_installed();

    die Cpanel::Exception->new('This functionality requires [asis,ModSecurity] to be installed.');
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private
# Name:
#   _trigger_hook
# Desc:
#   This function triggers the hook on Whostmgr::ModSecurity.
# Arguments:
#   - pre_or_post - a string that should be only "pre" or "post".
#   - event - a string that is the name of the api call.
#        example: ModSecurity::modsec_add_rule
# Returns:
#   - Nothing is returned.
#-------------------------------------------------------------------------------------------------
sub _trigger_hook {
    my ( $pre_or_post, $event ) = @_;

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => $event,
            'stage'    => $pre_or_post,
        },
    );

    return;
}

1;
