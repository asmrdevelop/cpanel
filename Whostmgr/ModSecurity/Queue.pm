
# cpanel - Whostmgr/ModSecurity/Queue.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Queue;

use strict;
use Whostmgr::ModSecurity::Chunk         ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::LoadModule                   ();
use Cpanel::Autodie                      ();
use Cpanel::Exception                    ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();
use Cpanel::Locale 'lh';
use Cpanel::Transaction::File::JSON         ();    # PPI USE OK -- used by _load
use Cpanel::Transaction::File::JSONReader   ();    # PPI USE OK -- used by _load
use Whostmgr::ModSecurity                   ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();
use Whostmgr::ModSecurity::Parse            ();    # also provides Whostmgr::ModSecurity::Parse::Disablements
use Whostmgr::ModSecurity::TransactionLog   ();
use Whostmgr::ModSecurity::Chunk::Diff      ();
use subs 'EXISTING_CHUNK', 'NEW_CHUNK';

=head1 NAME

Whostmgr::ModSecurity::Queue

=head1 DESCRIPTION

A class representing a queue of actions to be performed on a ModSecurity configuration
file.

The queue is stored on disk next to the config file itself as a JSON file.

=head1 SYNOPSIS

Queue some actions:

  my $queue = Whostmgr::ModSecurity::Queue->new(config => 'modsec2.example.conf', mode => 'rw');
  $queue->queue('disable_rule', 1234567);
  $queue->queue('disable_rule', 2345678);
  $queue->queue('add_rule', q|SecRule REQUEST_URI "test" "deny,id:'8888888'"\n|);
  $queue->queue('undisable_rule', 1234567);
  $queue->queue('disable_rule', 8888888); # This queue depends on an earlier queue
  $queue->queue('remove_rule', 7654321);

Come back later and deploy them:

  my $queue = Whostmgr::ModSecurity::Queue->new('modsec2.example.conf', mode => 'rw');
  $queue->deploy();

=head1 METHODS

=head2 new()

=head3 Arguments

'config': The relative path to the config file in question, based from the Apache
configuration prefix. Note: This is the name of the live copy, not the queue file
itself.

=cut

sub new {
    my ( $package, @args ) = @_;
    my $self = {@args};
    @$self{qw(live staging)} = Whostmgr::ModSecurity::get_config_paths( $self->{config} );
    bless $self, $package;

    $self->_load();

    return $self;
}

sub _load {
    my ($self) = @_;
    my $class = 'Cpanel::Transaction::File::JSON';
    $class = 'Cpanel::Transaction::File::JSONReader' if $self->{mode} && $self->{mode} eq 'ro';
    $self->{transaction} = $class->new( path => $self->{staging} );
    my $data = $self->{transaction}->get_data();
    return ( $self->{contents} = ref($data) eq 'ARRAY' ? $data : undef );
}

sub _save {
    my ($self) = @_;
    my $transaction = $self->{transaction};
    $transaction->set_data( $self->{contents} );

    #TODO: Make this report error messages.
    return ( $transaction->save() )[0];
}

sub done {
    my ($self) = @_;
    my $transaction = delete $self->{transaction};
    return 1 if !$transaction or ref $transaction eq 'Cpanel::Transaction::File::JSONReader';    # Nothing to be done if read-only

    #TODO: Teach this to report error messages
    my ( $abort, $err ) = $transaction->abort();

    if ( ref $self->{contents} ne 'ARRAY' or !@{ $self->{contents} } ) {
        unlink $self->{staging};                                                                 # If the transaction is finalized such that there are no entries, remove the JSON file rather than leave a blank one.
    }
    return $abort;
}

=head2 queue(ACTION, ARG, ...)

Queue an action to perform on a list of chunks. The available actions and their
arguments are:

  - disable_rule          ID
        Disable the rule given by ID (this is a ModSecurity rule id)

  - undisable_rule        ID
        Undisable the rule given by ID

  - add_rule              RULE_TEXT
        Add one or more rules as specified by RULE_TEXT (may be multi-line)

  - remove_rule           ID
        Remove the rule given by ID

  - remove_rule_matching  RULE_TEXT
        Remove any rule (zero or more) exactly matching RULE_TEXT as a string.

  - edit_rule             ID    RULE_TEXT
        Locate the rule with id ID in the config file, and replace with the
        rule specified by RULE_TEXT.

  - set_directive         DIRECTIVE    VALUE
        Locate any occurrence of the directive given by DIRECTIVE in the
        config file and set its value to VALUE (only one argument is possible
        currently). If the directive is not yet present, it will be added.

  - remove_directive      DIRECTIVE
        Removes any/all instances of DIRECTIVE, regardless of its argument(s).

  - set_config_text       TEXT
        Set the entire text contents of the configuration file.

  - assemble_config_text  TEXT    FLAGS
        Set the entire text contents of the configuration file, allowing it to
        be uploaded in multiple pieces. The FLAGS argument is a hash ref
        containing either, both, or neither of:
          'init':  Boolean indicating that this is the first piece in
                   the series.
          'final': Boolean indicating that this is the last piece
                   the series.

The behaviors of these actions are implemented in the playback() method.

=head3 Throws

This method will throw a Cpanel::Exception::ModSecurity::DuplicateQueueItem exception
if the queued item is an obvious duplicate.

It will also throw generic perl exceptions if any other validation fails.

=cut

sub queue {
    my ( $self, $action, @arguments ) = @_;

    if ( !$self->{skip_installed_check} && !Whostmgr::ModSecurity::has_modsecurity_installed() ) {
        die Cpanel::Exception::create( 'ModSecurity::NotInstalled', [ action => $action, arguments => \@arguments ] );
    }

    die lh()->maketext(q{You cannot specify an empty action.}) . "\n" if !$action;

    $self->_validate_action( $action, @arguments );

    $self->{contents} = [] if ref $self->{contents} ne 'ARRAY';

    # If this is a duplicate of the last item in the queue, silently ignore it.
    die Cpanel::Exception::create( 'ModSecurity::DuplicateQueueItem', [ action => $action, arguments => \@arguments ] ) if $self->_last_action_in_queue_is( $action, @arguments );

    push @{ $self->{contents} }, [ $action, @arguments ];

    $self->_save() or die lh()->maketext( q{The system could not save the queue file “[_1]”.}, $self->{config} ) . "\n";

    Whostmgr::ModSecurity::TransactionLog::log( operation => $action, arguments => \@arguments );

    return 1;
}

# To be used for validating that an action is valid before allowing it to be queued.
sub _validate_action {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, $action, @arguments ) = @_;

    if ( 'ARRAY' eq ref $self->{contents} and my $last_queued_action = $self->{contents}[-1] ) {
        my ( $lqa_name, $lqa_text, $lqa_flags ) = @$last_queued_action;
        if ( $action ne 'assemble_config_text' && $lqa_name eq 'assemble_config_text' && !$lqa_flags->{final} ) {

            # In contrast to set_config_text, which rebuilds the entire config text immediately and recreates the chunk
            # objects for subsequent queued actions to operate on, an assemble_config_text action that is not final will
            # leave the queue in an intermediate state off of which other actions can't build. This is because there's
            # no way to recreate the chunk objects for subsequent actions when the new config text hasn't been fully
            # uploaded yet, and so the only valid action is another assemble_config_text.
            die lh()->maketext( q{You cannot queue another type of the action “[_1]” until you finalize the current [asis,assemble_config_text] action in the queue.}, $lqa_name ) . "\n";
        }
    }

    if ( $action eq 'disable_rule' ) {
        die lh()->maketext(q{The [asis,disable_rule] argument must be a positive integer.}) . "\n" if !_is_positive_integer( $arguments[0] );
        $self->_assert_id_exists( $arguments[0] );
        return 1;
    }
    elsif ( $action eq 'undisable_rule' ) {
        die lh()->maketext(q{The [asis,undisable_rule] argument must be a positive integer.}) . "\n" if !_is_positive_integer( $arguments[0] );
        $self->_assert_id_exists( $arguments[0] );
        return 1;
    }
    elsif ( $action eq 'add_rule' ) {
        my ($rule_text) = @arguments;

        my $chunk = Whostmgr::ModSecurity::Chunk->new( export_as => 'self', config => $self->{config} );
        $chunk->append($rule_text);

        if ( $self->_id_exists( $chunk->id ) ) {
            die lh()->maketext( q{You cannot add a rule with the ID “[_1]” because another rule with the same ID already exists in the “[_2]” configuration file.}, $chunk->id, $self->{config} ) . "\n";
        }

        # The argument to add_rule is a piece of text containing one or more configuration directives.
        # We need to verify that processing that directive in addition to the existing configuration
        # doesn't result in an error.
        return Whostmgr::ModSecurity::validate_rule($rule_text);    # throws an exception if invalid
    }
    elsif ( $action eq 'remove_rule' ) {
        die lh()->maketext(q{The [asis,remove_rule] argument must be a positive integer.}) . "\n" if !_is_positive_integer( $arguments[0] );
        $self->_assert_id_exists( $arguments[0] );
        return 1;
    }
    elsif ( $action eq 'remove_rule_matching' ) {
        die lh()->maketext(q{The [asis,remove_rule_matching] argument must be at least one character long.}) . "\n" if !length( $arguments[0] );
        return 1;
    }
    elsif ( $action eq 'remove_directive' ) {
        die lh()->maketext(q{The [asis,remove_directive] argument must be at least one character long.}) . "\n" if !length( $arguments[0] );
        return 1;
    }
    elsif ( $action eq 'set_directive' ) {
        die lh()->maketext(q{The [asis,set_directive] action requires two arguments.}) . "\n" if @arguments != 2;
        return 1;
    }
    elsif ( $action eq 'edit_rule' ) {
        my ( $id, $rule_text ) = @arguments;

        $self->_assert_id_exists($id);

        # Step 1: Ensure that this doesn't cause a duplicate id within the same file, which
        # would break the individual rule editor (which needs to access rules by id).
        my $amended_rule = Whostmgr::ModSecurity::Chunk->new( export_as => 'self', config => $self->{config} );
        $amended_rule->append($rule_text);
        if ( $amended_rule->id != $id && $self->_id_exists( $amended_rule->id ) ) {
            die lh()->maketext( q{The system cannot change the [asis,id] from “[_1]” to “[_2]” because that [asis,id] already exists.}, $id, $amended_rule->id ) . "\n";
        }

        # Step 2: If the rule id is not being changed, fake the id before doing Apache validation
        # because otherwise Apache would detect the test rule as a duplicate of the real one during
        # our validation attempt.
        if ( $amended_rule->id == $id ) {
            my $temp_id = 1_000_000_001;
            $rule_text =~ s{id:(["']?)(\d+)}{id:$1$temp_id};
        }

        # Step 3: Do the actual Apache validation of the rule.
        return Whostmgr::ModSecurity::validate_rule($rule_text);
    }
    elsif ( $action eq 'remove_rule' ) {
        die lh()->maketext(q{The [asis,remove_rule] argument must be a positive integer.}) . "\n" if !_is_positive_integer( $arguments[0] );
        return 1;
    }
    elsif ( $action eq 'set_config_text' ) {
        my ($new_text) = @arguments;

        _fix_trailing_newline( \$new_text );
        my ($new_chunks) = @{ Whostmgr::ModSecurity::Parse::get_chunk_objs_from_text( $new_text, $self->{config} ) }{'chunks'};
        _check_chunk_ids($new_chunks);

        return 1;
    }
    elsif ( $action eq 'assemble_config_text' ) {
        my ( $piece_text, $flags ) = @arguments;
        require Carp;
        Carp::croak( lh()->maketext('You must provide the text input for the function [asis,assemble_config_text].') ) if !defined $piece_text;
        Carp::croak( lh()->maketext('You must specify the flags for the function [asis,assemble_config_text].') )      if ref $flags ne 'HASH';

        _fix_trailing_newline( \$piece_text );

        if ( $flags->{final} ) {

            # Without making any permanent changes, play back the queue up until this final assemble_config_text,
            # which will leave behind _accumulated_text for us to consider during validation here.
            $self->playback();
            my $new_text = ( $self->{_accumulated_text} || '' ) . $piece_text;

            my ($new_chunks) = @{ Whostmgr::ModSecurity::Parse::get_chunk_objs_from_text( $new_text, $self->{config} ) }{'chunks'};
            eval { _check_chunk_ids($new_chunks); };
            if ( my $exception = $@ ) {

                # This will make and save an actual change to the queue
                $self->_pop_matching( sub { $_[0] eq 'assemble_config_text' } );
                die $exception;
            }
        }

        return 1;
    }

    die lh()->maketext( q{That is not a valid action: [_1]}, $action ) . "\n";
}

# Given a queue A(1) B(1) C(1) B(2) B(3) in which you request
# to pop any B action, the remaining queue will be:
#   A(1) B(1) C(1)
sub _pop_matching {
    my ( $self, $condition ) = @_;

    my $updated;
    while ('ARRAY' eq ref $self->{contents}
        && 'ARRAY' eq ref $self->{contents}[-1]
        && $condition->( @{ $self->{contents}[-1] } ) ) {
        pop @{ $self->{contents} };
        $updated = 1;
    }

    if ($updated) {
        $self->_save() || die lh()->maketext( q{The system could not remove the [asis,assemble_config_text] actions from the queue for “[_1]”.}, $self->{config} ) . "\n";
    }

    return 1;
}

sub _id_exists {
    my ( $self, $id ) = @_;
    return if !$id;
    my $up_to_date_chunks = $self->playback();
    if ( !grep { $_->id && $_->id == $id } @$up_to_date_chunks ) {
        return 0;
    }
    return 1;
}

sub _assert_id_exists {
    my ( $self, $id ) = @_;
    if ( !$self->_id_exists($id) ) {
        die lh()->maketext( q{The rule with id “[_1]” does not exist.}, $id ) . "\n";
    }
    return 1;
}

=head2 queue_and_done(ACTION, ARG, ...)

Works exactly like queue(), but with the following difference:

Immediately perform a done() after the queue either succeeds or fails,
but continue to throw any exception on to the caller. This special-case
wrapper is meant to reduce caller clutter from the exception handling.

=head3 Throws

This method throws the same exceptions as queue().

=cut

sub queue_and_done {
    my ( $self, $action, @arguments ) = @_;
    my $queue_ok = eval { $self->queue( $action, @arguments ); };
    my $error    = $@;
    my $done_ok  = $self->done;                                     # Make sure this is called regardless of whether queue() threw an exception.
    die $error if $error;                                           # Should already be a decent locale string from queue()
    return ( $queue_ok && $done_ok );
}

=head2 playback()

=head3 Description

Loads the contents of the config file in question, then plays back the queue against
the parsed chunks.

=head3 Returns

The altered chunk objects.

=cut

sub playback {
    my ( $self, %args ) = @_;
    my $parsed = Whostmgr::ModSecurity::Parse::get_chunk_objs_live( $self->{live} );
    my $chunks = $parsed->{chunks};

    my $disablements = Whostmgr::ModSecurity::Parse::Disablements->new;    # PPI NO PARSE - provided by Whostmgr::ModSecurity::Parse
    my %original_ids = map { $_->id => 1 } @$chunks;

    # This saves a lot of time when operating on a large rule set and multiple actions are queued.
    # See t/Whostmgr-ModSecurity-Configure_benchmark.t.
    my @interesting_chunks = $self->_find_interesting_chunks($chunks);

    # The list of actions from the queue must be the outer loop because it's possible for subsequent
    # actions to depend on the action that preceded it.
    for my $action ( @{ $self->{contents} } ) {
        my ( $func, @arg ) = @$action;

        my $satisfied;

        if ( $func eq 'assemble_config_text' ) {
            my ( $piece_text, $flags ) = @arg;

            if ( $flags->{init} ) {
                $self->{_accumulated_text} = '';
            }

            _fix_trailing_newline( \$piece_text );
            $self->{_accumulated_text} .= $piece_text;

            if ( $flags->{final} ) {
                my $new_text = delete $self->{_accumulated_text};
                my ($regenerated_chunks) = @{ Whostmgr::ModSecurity::Parse::get_chunk_objs_from_text( $new_text, $self->{config} ) }{'chunks'};

                # Update the chunk list based on the chunks freshly generated from the submitted text. These new chunks are
                # what will continue to be operated on during the rest of playback, and what will be returned.
                Whostmgr::ModSecurity::Chunk::Diff::annotate_pending( annotate => $regenerated_chunks, reference => $chunks );
                $chunks = $regenerated_chunks;

                # Check for rule ids that were either added or deleted during this assemble_config_text operation.
                #
                # NOTE: An id change amounts to a remove + add, and we make no effort in assemble_config_text to track
                # these id changes because there would be too much guesswork involved. Anyone who wants disablements to
                # be preserved across id changes needs to use the individual edit_rule interface.
                my %updated_ids = map { $_->id => 1 } @$chunks;
                my %added_ids   = map { $_     => 1 } grep { !$original_ids{$_} } keys %updated_ids;
                my %removed_ids = map { $_     => 1 } grep { !$updated_ids{$_} } keys %original_ids;

                # Clean up old disablements to match new rule list for this file.
                for my $already_disabled_id ( keys %{ $disablements->all } ) {

                    # If a rule that was either added or deleted during this operation already had a SecRuleRemoveById present,
                    # we want to delete that SecRuleRemoveById.
                    if (   $added_ids{$already_disabled_id}
                        || $removed_ids{$already_disabled_id} ) {
                        Whostmgr::ModSecurity::ModsecCpanelConf->new->remove_srrbi($already_disabled_id) if $args{deploy};
                    }
                }

                @interesting_chunks = $self->_find_interesting_chunks($chunks);
                $self->{altered} = 1;
            }
            next;
        }

        # Operations that apply to existing chunks that have ids. We loop only over the interesting
        # chunks to save iterations, but these are some of the same objects stored in $chunks that
        # will be returned at the end.
        for my $chunk (@interesting_chunks) {
            last if $func eq 'add_rule';

            # For each chunk, initially assume that chunk will trigger a change to the underlying
            # file. Reverse this assumption only in two cases:
            #   (1) The chunk didn't match our criteria (common case).
            #   (2) We are (un)disabling a vendor rule.
            my $altered = 1;

            if ( $func eq 'disable_rule' && $arg[0] eq $chunk->id ) {
                Whostmgr::ModSecurity::ModsecCpanelConf->new->add_srrbi( $arg[0], $self->vendor_if_any ) if $args{deploy};
                $altered = 0;
                $chunk->disabled(1);
                $chunk->staged(1);
                $satisfied = $chunk;
            }
            elsif ( $func eq 'undisable_rule' && $arg[0] eq $chunk->id ) {
                if ( $chunk->disabled ) {
                    Whostmgr::ModSecurity::ModsecCpanelConf->new->remove_srrbi( $arg[0] ) if $args{deploy};
                    $altered = 0;
                    $chunk->disabled(0);
                    $chunk->staged(1);
                }
                $satisfied = $chunk;
            }
            elsif ( $func eq 'remove_rule' && $arg[0] eq $chunk->id ) {
                $chunk->text('');
                $chunk->disabled(0);
                $chunk->staged(1);
                $satisfied = $chunk;
            }
            elsif ( $func eq 'remove_rule_matching' && $chunk->text =~ m{\A\s*\Q$arg[0]\E\s*\z} ) {
                $chunk->text('');
                $chunk->disabled(0);
                $chunk->staged(1);
                $satisfied = $chunk;
            }
            elsif ( $func eq 'edit_rule' && $arg[0] eq $chunk->id ) {

                my $was_disabled = $chunk->disabled;
                $chunk->text( $arg[1] );
                $chunk->staged(1);
                $chunk->disabled($was_disabled);    # later actions in the queue may depend on the knowledge of whether this chunk is disabled

                # If the rule was disabled before we changed it, updated the rule id for the SecRuleRemoveById also.
                if ( $was_disabled && $args{deploy} && $chunk->id != $arg[0] ) {
                    Whostmgr::ModSecurity::ModsecCpanelConf->new->add_srrbi( $chunk->id, $self->vendor_if_any );
                    Whostmgr::ModSecurity::ModsecCpanelConf->new->remove_srrbi( $arg[0] );
                }

                $satisfied = $chunk;
            }
            elsif ( $func eq 'remove_directive' && $chunk->text =~ m{\A\s*\Q$arg[0]\E\s+} ) {
                $chunk->text('');
                $chunk->disabled(0);
                $chunk->staged(1);
                $satisfied = $chunk;
            }

            # Set the value of a directive of which only one instance can exist
            elsif ( $func eq 'set_directive' && $chunk->text =~ m{\A\s*\Q$arg[0]\E\s+} ) {

                # If the current action has already been satisfied by a previous chunk, the current
                # chunk must be a duplicate of the same directive. Clear the previous instance of
                # this directive in order to deduplicate, and then update this one.
                if ($satisfied) {
                    $satisfied->text('');
                }
                $chunk->text( join ' ', $arg[0], qq{"$arg[1]"\n} );
                $chunk->disabled(0);
                $chunk->staged(1);
                $satisfied = $chunk;
            }
            else {
                $altered = 0;
            }

            # Keep track of whether we have made any changes that will result in the config file this queue
            # represents being altered. If not, the save can be skipped.
            $self->{altered} ||= $altered;
        }

        my $new_chunk = Whostmgr::ModSecurity::Chunk->new( export_as => 'self', config => $self->{config} );

        # Operations that apply at the end of the list of chunks
        if ( $func eq 'add_rule' ) {
            $new_chunk->append( $arg[0] );
            $new_chunk->staged(1);
            $satisfied = $new_chunk;
        }

        # If we're setting a directive for which only one instance can exist, and it wasn't already
        # found in the file, add it.
        if ( $func eq 'set_directive' && !$satisfied ) {
            $new_chunk->append( join ' ', $arg[0], qq{"$arg[1]"} );
            $new_chunk->staged(1);
            $satisfied = $new_chunk;
        }

        if ( $satisfied eq $new_chunk ) {    # same instance
            push @$chunks, $new_chunk;

            # Also push to @interesting_chunks, because if there are any other queued actions that might affect
            # this chunk, it wasn't able to be added to @interesting chunks at the top of the function, since
            # the chunk didn't exist at that point. (If there aren't then it doesn't matter.)
            push @interesting_chunks, $new_chunk;

            $self->{altered} ||= 1;
        }

        die lh()->maketext( q{The action “[_1]” is invalid because no directive exists which matches the criteria.}, $func ) . "\n" if !$satisfied;
    }

    my ( @include_chunks, @other_chunks );
    for my $c (@$chunks) {
        next if $c->empty;
        if (   $self->{config} eq Whostmgr::ModSecurity::modsec_cpanel_conf()
            && $c->is_include ) {
            push @include_chunks, $c;
        }
        else {
            push @other_chunks, $c;
        }
    }

    return [ @include_chunks, @other_chunks ];
}

=head2 deploy()

=head3 Description

Deploys the queue to the live config file.

=cut

sub deploy {
    my ($self) = @_;
    my ( $abs_config_path, $abs_config_path_stage ) = Whostmgr::ModSecurity::get_config_paths( $self->{config} );

    # Ensure that, if we die before moving the current config aside, we won't accidentally restore a leftover backup.
    unlink $abs_config_path . '.PREVIOUS';

    my $ok = eval {

        # This part must always be done
        my $altered_chunks = $self->playback( deploy => 1 );

        # If the actions performed during playback() above were ones that didn't cause the
        # original config file to be altered, skip this part where it gets rewritten.
        if ( $self->{altered} ) {

            my $prev = $abs_config_path . '.PREVIOUS';
            Cpanel::Autodie::rename( $abs_config_path, $prev );

            open my $cfg_fh, '>', $abs_config_path or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $abs_config_path, error => $! ] );

            for my $chunk (@$altered_chunks) {
                next if $chunk->empty;
                print {$cfg_fh} $chunk->text_for_config_file;
                print {$cfg_fh} $chunk->punctuate;
            }
            close $cfg_fh;
        }

        1;
    };
    if ( !$ok ) {
        my $err  = $@;
        my $prev = $abs_config_path . '.PREVIOUS';
        rename $prev, $abs_config_path;
        die lh()->maketext( q{The system could not deploy changes for “[_1]”: [_2]}, $self->{config}, $err ) . "\n";    # unconditional; not related to the rename immediately before it
    }

    Whostmgr::ModSecurity::TransactionLog::log( operation => 'deploy_rule_changes', arguments => { config => $self->{config} } );

    if ( eval { Whostmgr::ModSecurity::validate_httpd_config() } ) {
        unless ( $self->{skip_restart} ) {
            _restart_httpd();
        }

        unlink $abs_config_path . '.STAGE';
        unlink $abs_config_path . '.PREVIOUS';

        # If we successfully deployed the entire queue (causing the json file to be deleted), update
        # in-memory knowledge of contents so subsequent calls to deploy don't double-deploy previous
        # actions.
        $self->{contents} = undef;

        return 1;
    }
    else {
        my $validation_error = $@;
        rename $abs_config_path,               $abs_config_path . '.FAILED';
        rename $abs_config_path . '.PREVIOUS', $abs_config_path or die lh()->maketext( q{The new configuration is not valid. Additionally, the system could not restore the previous configuration: [_1]}, $@ . $! ) . "\n";
        die $validation_error;    # assumed to already be a good locale string from validate_httpd_config()
    }

    return 1;
}

sub vendor_if_any {
    my ($self) = @_;
    return Whostmgr::ModSecurity::extract_vendor_id_from_config_name( $self->{config} );
}

sub _last_action_in_queue_is {
    my ( $self, $action, @arguments ) = @_;
    my $last_action = ( $self->{contents} || [] )->[-1];
    if ( ref $last_action eq 'ARRAY' ) {
        Cpanel::LoadModule::load_perl_module('Data::Compare');
        return Data::Compare::Compare( $last_action, [ $action, @arguments ] );
    }
    return;
}

sub _validate_rule {
    my $rule = shift;
    return Cpanel::SafeRun::Errors::saferunallerrors( Whostmgr::ModSecurity::actual_httpd_bin(), '-t', '-c', $rule );
}

sub _restart_httpd {
    return Cpanel::HttpUtils::ApRestart::BgSafe::restart();
}

sub _is_positive_integer {
    my $n = shift;
    return if !defined($n);
    return $n =~ m{^[1-9][0-9]*$};
}

# Given an array of chunk objects, returns those that are expected to be of relevance for edits in the queue.
# Rationale: If there are N chunks and M edits queued, there would normally have to be N*M iterations in the
# main loop. By pre-grepping for only the interesting chunks, the size of N may be shrunk considerably
# in some cases.
sub _find_interesting_chunks {
    my ( $self, $chunks ) = @_;
    my %interesting_ids    = map  { ref($_) eq 'ARRAY' && $_->[1] =~ /^\d+$/ ? ( $_->[1] => 1 ) : () } @{ $self->{contents} || [] };
    my @interesting_chunks = grep { !$_->id                                                                                 || $interesting_ids{ $_->id } } @$chunks;
    return @interesting_chunks;
}

sub _check_chunk_ids {
    my ($chunks) = @_;
    my %seen;
    for my $c (@$chunks) {

        # Normally we leave it to Apache to detect these duplicate ID or lack-of-ID problems during individual
        # rule updates ( along with  the various other checks it does), but in the case of the mass text editor,
        # we need to watch out for the problems here, because no Apache check will be done until deployment.
        if ( $c->id && $seen{ $c->id }++ ) {
            die lh()->maketext( q{Rule ID “[_1]” is duplicated in this configuration file.}, $c->id ) . "\n";
        }

        if ( $c->text =~ m{^Sec(?:Rule|Action)\s+}m && !$c->id ) {
            die lh()->maketext( q{The following rule did not have an ID: [_1]}, $c->text ) . "\n";
        }
    }
    return 1;
}

sub _fix_trailing_newline {
    my ($piece_text_ref) = @_;
    $$piece_text_ref .= "\n" if substr $$piece_text_ref, -1, 1 ne "\n";
    return;
}

1;
