
# cpanel - Whostmgr/ModSecurity/Configure.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Configure;

use strict;
use Carp                                    ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();
use Fcntl                                   ();
use File::Find;

use Cpanel::Locale 'lh';
use File::Find                   ();
use Whostmgr::ModSecurity        ();
use Whostmgr::ModSecurity::Chunk ();
use Whostmgr::ModSecurity::Parse ();
use Whostmgr::ModSecurity::Queue ();

=head1 SUBROUTINES

=head2 disable_rule()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The id of the rule to disable

The change will be made in the staging copy of the configuration file.

=cut

sub disable_rule {
    my ( $config, $id ) = @_;
    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    return $queue->queue_and_done( 'disable_rule', $id );
}

=head2 undisable_rule()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The id of the rule to disable

The change will be made in the staging copy of the configuration file.

The name "undisable" (as opposed to "enable") was chosen because it reflects the fact
that a rule being disabled is an abnormal condition caused by request of the user, and
undisabling restores the default state.

=cut

sub undisable_rule {
    my ( $config, $id ) = @_;
    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    return $queue->queue_and_done( 'undisable_rule', $id );
}

=head2 check_rule()

  Arguments:
    - The rule to be checked

  Returns:

    If valid:
      - A true value
      - The string "OK"

    If invalid:
      - A false value
      - The exception that was thrown by the validation function, for presentation to the user

  Note that this function returns the exception text rather than throwing it because this validation
  failure is not actually a failure of check_rule(), which still achieved its goal of determining
  whether the rule was valid or not.

=cut

sub check_rule {
    my ($rule_text) = @_;
    wantarray or Carp::croak( lh()->maketext(q{Calling this function in scalar context is incorrect.}) );    # shouldn't be a user-facing error
    my $valid     = eval { Whostmgr::ModSecurity::validate_rule($rule_text) };
    my $exception = $@;
    if ($valid) {
        return ( 1, "OK" );
    }
    return ( 0, $exception );
}

=head2 add_rule()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The rule text to be added

The rule will be added to the end of the staging copy of the configuration file.

=cut

sub add_rule {
    my ( $config, $rule_text ) = @_;

    # This chunk is created solely for the benefit of the caller, as additional convenience info.
    # (Even setting the staged flag is just for the convenience / consistency with expectations
    # of the caller here)
    my $chunk = Whostmgr::ModSecurity::Chunk->new( export_as => 'plain', config => $config );
    $chunk->append($rule_text);
    $chunk->staged(1);

    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    $queue->queue_and_done( 'add_rule', $rule_text );

    return $chunk->export;
}

=head2 remove_rule()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The id of the rule to be removed.

Note: It's currently not possible to use this API to remove a chunk of text that
doesn't have a mod_security rule id.

=cut

sub remove_rule {
    my ( $config, $id ) = @_;

    # if the rule is disabled, enable it, for tidyness' sake...
    eval { undisable_rule( $config, $id ) };
    my $exception = $@;

    # If an exception other than "duplicate queue item" occurred, re-throw the exception. Otherwise ignore,
    # since it's harmless for the undisable to be discarded as a duplicate.
    die $exception if $exception && 'Cpanel::Exception::ModSecurity::DuplicateQueueItem' ne ref $exception;

    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    return $queue->queue_and_done( 'remove_rule', $id );
}

=head2 remove_rule_matching()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The full exact text of the rule to be removed.

This function is currently for backend use only and doesn't have a corresponding
API endpoint.

=cut

sub remove_rule_matching {
    my ( $config, $id ) = @_;
    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    return $queue->queue_and_done( 'remove_rule_matching', $id );
}

=head2 edit_rule()

  Arguments:

=cut

sub edit_rule {
    my ( $config, $id, $rule_text ) = @_;

    my $chunk = Whostmgr::ModSecurity::Chunk->new( export_as => 'plain', config => $config );
    $chunk->append($rule_text);
    $chunk->staged(1);

    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    $queue->queue_and_done( 'edit_rule', $id, $rule_text );

    return $chunk->export;
}

=head2 deploy_rule_changes()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)

Deploys the staged rule changes to the live copy of the configuration file, validates the
httpd configuration, and queues an httpd restart.

=cut

sub deploy_rule_changes {
    my ($config) = @_;
    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );
    eval { $queue->deploy() };
    my $error = $@;
    $queue->done;
    die $error if $error;
    return 1;
}

=head2 discard_rule_changes()

Discard the staging copy of the specified config file.

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)

=cut

sub discard_rule_changes {
    my ($config) = @_;
    my ( $abs_config_path, $abs_config_path_stage ) = Whostmgr::ModSecurity::get_config_paths($config);
    if ( -f $abs_config_path_stage ) {
        unlink $abs_config_path_stage or die lh()->maketext( q{The system could not remove the file “[_1]”: [_2]}, $abs_config_path_stage, $! ) . "\n";
        return 1;
    }
    die lh()->maketext( q{The system could not discard the rule changes because the path “[_1]” does not exist.}, $abs_config_path_stage ) . "\n";
}

=head2 get_configs_with_changes_pending()

Determine if there are rule changes pending.

  Arguments:
    - none

Returns a list of configuration files that have pending changes.

=cut

sub get_configs_with_changes_pending {
    my $configurations_dir = Whostmgr::ModSecurity::config_prefix();
    my $suffix             = quotemeta( Whostmgr::ModSecurity::stage_suffix() );
    my @files;
    File::Find::find(
        sub {
            my $thisfile = $File::Find::name;
            if ( $thisfile =~ /$suffix$/ ) {
                $thisfile =~ s/$suffix$//;
                my $configs = quotemeta($configurations_dir);
                $thisfile =~ s~^$configs/~~;
                push @files, $thisfile;
            }
        },
        $configurations_dir
    );
    return \@files;
}

=head2 is_config_active()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - (Optional) An array ref which, if present and declared in the caller's scope
      before the beginning of a mass operation, will facilitate caching for better
      performance.

Returns a boolean value indicating whether the config in question is active (i.e. included
for httpd).

=cut

sub is_config_active {
    my ( $config, $cache ) = @_;
    $cache = [] if ref $cache ne 'ARRAY';
    $cache->[0] ||= Whostmgr::ModSecurity::ModsecCpanelConf->new->active_configs();
    return ( $cache->[0]{$config} ? 1 : 0 );
}

=head2 make_config_active()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)

Makes the config active by adding an include for it.

=cut

sub make_config_active {
    my ($config) = @_;
    return Whostmgr::ModSecurity::ModsecCpanelConf->new->include($config);
}

=head2 make_config_inactive()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)

Makes the config inactive by removing its include.

=cut

sub make_config_inactive {
    my ($config) = @_;
    return Whostmgr::ModSecurity::ModsecCpanelConf->new->uninclude($config);
}

=head2 get_config_text()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - If true, returns the chunks as an array, if false as a text blob.

  Returns:
    - The entire text contents of the configuration file, with any staged changes taken into account.

=cut

sub get_config_text {
    my ( $config, $pagable ) = @_;

    # Get the contents of the file, incorporating in any staged edits
    my $parsed = Whostmgr::ModSecurity::Parse::get_chunk_objs( Whostmgr::ModSecurity::get_safe_config_filename($config) );
    my @chunks = map { $_->text_for_config_file . $_->punctuate } @{ $parsed->{chunks} };
    my $config_text;
    if ( !$pagable ) {
        $config_text = join '', @chunks;
    }
    else {
        $config_text = \@chunks;
    }

    return $config_text;
}

=head2 set_config_text()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The new contents of the file
    - Boolean flag: Whether to also deploy the changes

Updates the entire contents of a mod_security configuration file with the supplied text.

=cut

sub set_config_text {
    my ( $config, $text, $deploy ) = @_;

    # implemented by queueing an assemble_config_text which is marked as both the first and last
    return assemble_config_text( $config, $text, { init => 1, final => 1 }, $deploy );
}

=head2 assemble_config_text()

  Arguments:
    - Relative path to the configuration file (based from Apache config prefix)
    - The new contents of the file
    - Flags: Flags to pass to the queue action.
        'init': Indicates that this is the first piece of text.
        'final': Indicates that this is the last piece of text.
    - Boolean flag: Whether to also deploy the changes

It's possible to call assemble_config_text() with both 'init' and 'final' set, but
this is equivalent to set_config_text().

Updates the entire contents of a mod_security configuration file with the supplied text.

=cut

sub assemble_config_text {
    my ( $config, $text, $flags, $deploy ) = @_;
    my $queue = Whostmgr::ModSecurity::Queue->new( config => $config );

    my $exception;
    eval {
        $queue->queue( 'assemble_config_text', $text, $flags );
        if ($deploy) {
            $queue->deploy;
        }
    };
    $exception = $@;

    # Make sure the lock is released no matter what exception we might get
    $queue->done;

    die $exception if $exception;
    return 1;
}

1;
