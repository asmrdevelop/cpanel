
# cpanel - Whostmgr/ModSecurity/Parse.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Parse;

use strict;

use Whostmgr::ModSecurity        ();
use Whostmgr::ModSecurity::Queue ();
use Whostmgr::ModSecurity::Chunk ();
use Cpanel::Locale 'lh';

sub DIRECTIVE { return 1; }
sub CHAIN     { return 2; }
sub COMMENT   { return 3; }

=head1 NAME

Whostmgr::ModSecurity::Parse

=head1 SUBROUTINES

=head2 parse()

=head3 Arguments

$file: The absolute path to a mod_security config file. No sanitization is done on this filename,
so it is the caller's responsibility to make sure the file passed in is safe. If a staging copy
of the specified file exists, the rules will be read from there instead of from the file itself.

=head3 Returns

A hash ref containing:

  'chunks': An array ref containing multiple chunks. Each chunk is a hash ref containing:

      - 'id': The rule id, if any. This will be an empty string if there was no rule id (e.g., for a
          chunk of comment text not associated with a rule).

      - 'disabled': Boolean value indicating whether the rule is disabled in the configuration.

      - 'rule': The text of the rule itself, which may be multiple lines including more than one directive,
                plus related comments. The rule returned in this field will appear without the disabled marker
                comment, even if it is disabled.

      - 'staged_changes': A boolean, indicating whether or not the file has staged changes waiting to be
              committed. A one indicates truth, that there are staged changes. Zero indicates that
              there are no staged changes waiting.

=head3 Example return value

  { chunks => [
        { id => '',      rule => "# A comment that isn't actually a rule\n",               disabled => 0 },
        { id => 1234567, rule => qq|SecRule REQUEST_FILENAME "foo" "deny,id:'1234567'"\n|, disabled => 0 }
      ],
    staged_changes => 0
  }

=cut

sub parse {
    my ($file) = @_;
    return _parse( file => $file, export_as => 'plain' );
}

=head2 get_chunk_objs()

Behaves exactly like parse() except that the 'chunks' array contains Whostmgr::ModSecurity::Chunk
objects representing the rules instead of plain hashes. Whereas the hashes are more useful for
serializing, the objects are more useful for manipulating and storing back to disk.

=cut

sub get_chunk_objs {
    my ($file) = @_;
    return _parse( file => $file, export_as => 'self' );
}

=head2 get_chunk_objs_live()

Exactly like get_chunks_objs(), but never attempts to use the staging copy. This is needed when
initially setting up the staging copy, to ensure it doesn't attempt to erroneously read from its
own empty self.

=cut

sub get_chunk_objs_live {
    my ($file) = @_;
    return _parse( file => $file, export_as => 'self', skip_staging => 1 );
}

sub get_chunk_objs_from_text {
    my ( $text, $config ) = @_;
    return _parse( text => $text, export_as => 'self', config_for_chunks => $config );
}

sub _parse {
    my %args = @_;
    my ( $file, $text, $export_as ) = @args{qw(file text export_as)};
    if ( !grep { defined } $file, $text ) {
        die lh()->maketext(q{You must specify either a file to parse or the entire text contents of the file.}) . "\n";
    }

    my $config_for_chunks = $args{config_for_chunks} || Whostmgr::ModSecurity::to_relative($file);

    my $vendor = $file ? _is_vendor_config_file($file) : 0;

    # Trying to find the queue file for something that's not a file would be nonsensical.
    $args{skip_staging} = 1 if $text;

    my $data_source = 0;

    # If there are changes already staged but not yet deployed, this function should return
    # that version of the file.
    my $staging_copy = ( $file || '' ) . Whostmgr::ModSecurity::stage_suffix();
    if ( !$args{skip_staging} && -f $staging_copy ) {
        my $queue  = Whostmgr::ModSecurity::Queue->new( config => Whostmgr::ModSecurity::to_relative($file), mode => 'ro' );
        my $chunks = [ map { $args{export_as} eq 'plain' ? $_->plain : $_ } @{ $queue->playback() } ];
        return {
            chunks         => $chunks,
            staged_changes => 1
        };
    }

    # Load the list of disabled rules
    my $disablements = Whostmgr::ModSecurity::Parse::Disablements->new();

    # Use the same interface for either reading a file line by line or examining a pre-buffered piece of text.
    # (Only one of these two parameters will be defined.)
    my $iter = Whostmgr::ModSecurity::Parse::Iterate->new( file => $file, text => $text );

    my @chunks;
    my ($this_chunk) = Whostmgr::ModSecurity::Chunk->new( export_as => $export_as, vendor => $vendor, config => $config_for_chunks );

    my $state = DIRECTIVE;
    while ( defined( my $line = $iter->next() ) ) {

      ACCUMULATE: {
            if ( $line =~ m{^.*\\[\015\012]*\z}m ) {
                my $next_line = $iter->next();
                if ( defined $next_line ) {
                    $line .= $next_line;
                    redo;
                }
            }
        }

        my $discovered;
        if ( $state == CHAIN ) {
            $discovered = $this_chunk->append($line);
        }

        # If this is neither a rule nor a comment, force it not to be appended to the existing chunk,
        # even if the preceding text was a comment. We only want that behavior for rules, not for
        # all directives.
        elsif ( $state == DIRECTIVE || ( !_is_rule($line) && !_is_comment($line) ) ) {

            # Check to see whether this rule was disabled using a SecRuleRemoveById, and if so, flag it as disabled.
            # NOTE: This correct_chunk call must be made in every place a chunk is pushed to the @chunks array.
            $disablements->correct_chunk($this_chunk);
            push @chunks, $this_chunk->export();
            $this_chunk = Whostmgr::ModSecurity::Chunk->new( export_as => $export_as, vendor => $vendor, config => $config_for_chunks );
            $discovered = $this_chunk->append($line);
        }
        elsif ( $state == COMMENT ) {
            $discovered = $this_chunk->append($line);
        }

        if    ( $discovered->{chain} )   { $state = CHAIN }      # If we discovered a chain action in this line, set chain state.
        elsif ( $discovered->{comment} ) { $state = COMMENT }    # If this line was a comment, set comment state.

        # If we were in comment state and got an empty line, that should end the run of comments,
        # and the subsequent line should not be appended to it, so start a new chunk.
        elsif ( $state == COMMENT && $discovered->{empty} ) {
            $disablements->correct_chunk($this_chunk);
            push @chunks, $this_chunk->export();
            $this_chunk = Whostmgr::ModSecurity::Chunk->new( export_as => $export_as, vendor => $vendor, config => $config_for_chunks );
            $state      = DIRECTIVE;
        }

        # Otherwise, if we were in comment state (and we already know we didn't discover an additional comment),
        # go ahead and append this directive to the same chunk as the comment, but leave comment state so it
        # doesn't continue to suck lines in.
        elsif ( $state == COMMENT ) {
            $state = DIRECTIVE;
        }

        # If we were in chain state and hit anything other than an empty line (and we already know we didn't
        # discover an additional chain action), leave chain state.
        elsif ( $state == CHAIN && !$discovered->{empty} ) {
            $state = DIRECTIVE;
        }
    }

    $iter->done();
    $disablements->correct_chunk($this_chunk);
    push @chunks, $this_chunk->export();
    return {
        chunks         => [ grep { ref($_) eq 'Whostmgr::ModSecurity::Chunk' ? !$_->empty : ( $_->{rule} =~ /\S/ ) } @chunks ],
        staged_changes => $data_source,
    };
}

my ( $config_prefix, $vendor_configs_dir );

sub _is_vendor_config_file {
    my ($file) = @_;
    $config_prefix      ||= Whostmgr::ModSecurity::config_prefix();
    $vendor_configs_dir ||= Whostmgr::ModSecurity::vendor_configs_dir();
    return $file =~ m{^$config_prefix/$vendor_configs_dir/}o ? 1 : 0;
}

sub _is_rule {
    my ($line) = @_;
    return $line =~ /^Sec(?:Rule|Action) /;
}

sub _is_comment {
    my ($line) = @_;
    return $line =~ /^#/;
}

{

    package Whostmgr::ModSecurity::Parse::Iterate;

    use Carp              ();
    use Cpanel::Exception ();

    sub new {
        my ( $package, %args ) = @_;
        my $self = {};
        bless $self, $package;
        if ( defined $args{file} ) {
            open $self->{_fh}, '<', $args{file} or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $args{file}, error => $! ] );
        }
        elsif ( defined $args{text} ) {
            $self->{_lines} = [ map { $_ . "\n" } split /\n/, $args{text} ];
            $self->{_index} = 0;
        }
        else { Carp::croak('Iterator was not set up correctly (need either file or text)') }
        return $self;
    }

    sub next {
        my ($self) = @_;
        if ( $self->{_fh} ) {
            return scalar readline $self->{_fh};
        }
        return $self->{_lines}->[ $self->{_index}++ ];
    }

    sub done {
        my ($self) = @_;
        return $self->{_fh} ? close $self->{_fh} : 1;
    }
}

{

    package Whostmgr::ModSecurity::Parse::Disablements;
    use Carp                                    ();
    use Whostmgr::ModSecurity                   ();
    use Whostmgr::ModSecurity::ModsecCpanelConf ();

    sub new {
        my ($package) = @_;
        my $self = {};
        bless $self, $package;

        my $mcc = Whostmgr::ModSecurity::ModsecCpanelConf->new;
        @$self{qw(disabled_rules active_configs active_vendors)} = ( $mcc->disabled_rules, $mcc->active_configs, $mcc->active_vendors );

        return $self;
    }

    # Given a chunk object, corrects its disabled state to match the disabled state for that id
    # as reflected in this object's disabled lists.
    sub correct_chunk {
        my ( $self, $chunk ) = @_;

        $chunk->disabled( $self->{disabled_rules}{ $chunk->id } ? 1 : 0 ) if $chunk->id;

        my $user_conf = Whostmgr::ModSecurity::modsec_user_conf();
        if ( $chunk->config =~ m{(?:modsec/)?\Q$user_conf\E} ) {
            $chunk->config_active(1);
            $chunk->vendor_active(1);
        }
        else {
            $chunk->config_active( $self->{active_configs}{ $chunk->config }    ? 1 : 0 ) if $chunk->config;
            $chunk->vendor_active( $self->{active_vendors}{ $chunk->vendor_id } ? 1 : 0 ) if $chunk->vendor_id;
        }

        return 1;
    }

    # Returns a hash ref in which keys that are present are rule ids that are disabled.
    sub all {
        my ($self) = @_;
        return $self->{disabled_rules};
    }
}

1;
