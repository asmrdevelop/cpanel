
# cpanel - Whostmgr/ModSecurity/Chunk.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::ModSecurity::Chunk

=head1 DESCRIPTION

Class describing a chunk of text from a mod_security config file which may be:

 (1) A 'rule': A group of one or more mod_security directives that belong together
     as a single unit.
 (2) Another directive
 (3) A comment or group of comments not attached to any other directives.

The purpose of using the chunk class, rather than a plain data structure, is to
encapsulate (and define/document) the logic for manipulating chunks.

=cut

package Whostmgr::ModSecurity::Chunk;

use strict;
use Carp                         ();
use Whostmgr::ModSecurity::Parse ();
use Cpanel::Exception            ();
use Cpanel::Locale 'lh';
use Whostmgr::ModSecurity                   ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();

=head1 METHODS

=head2 new()

Constructor arguments:

'export_as': (REQUIRED) A string, either 'plain' or 'self', that determines whether the export()
method will provide a plain data structure suitable for serializing or just a reference to the object
itself. The latter is used when making updates.

=cut

sub new {
    my ( $package, @args ) = @_;
    my $self = {};
    bless $self, $package;
    $self->_init();
    %$self = ( %$self, @args ) if @args;

    $self->{export_as} or Carp::croak("You must provide an 'export_as' value of either 'plain' or 'self'.");    # not a public-facing error

    return $self;
}

sub _init {
    my ($self) = @_;
    @$self{qw(id disabled staged vendor text meta_msg vendor_id config_active vendor_active)} = ( '', 0, 0, 0, '', '', '', '', '' );
    return;
}

=head2 $chunk->append($line)

=head3 Purpose

Appends one or more lines of text to the chunk.

=head3 Arguments:

$line: A string containing one or more lines of text to be appended to the chunk. If the line is a
mod_security directive that contains a rule id (currently SecRule and SecAction are supported), the
id of the chunk will be set.

=head3 Returns:

A hash ref of discovered attributes about the directive that was appended. Currently, the only key that
can be set is 'chain', if the appended directive is the start or continuation of a chain.

=cut

sub append {
    my ( $self, $line, $opts ) = @_;

    $opts ||= {};

    my %discovered;

    $discovered{comment} = 1 if $line =~ m{^\#(?:[^~].*)[\015\012]*$};
    $discovered{empty}   = 1 if $line =~ m{^\s*$};

    # If this is a SecRule, it gets some special handling. Other directives are just passed through as individual chunks.
    if ( my ( $variables, $operator, $actions ) = _parse_rule($line) ) {
        my @action_pieces = split /,/, $actions || '';

        for (@action_pieces) {
            my ($cleansed_action_piece) = m{\A [\s\\]* (.+?) [\s\\]* \z}x;
            next                   if !defined($cleansed_action_piece);
            $discovered{chain} = 1 if $cleansed_action_piece eq 'chain';    # If this SecRule is the beginning or continuation of a chain, record this info for caller's benefit

            if ( my ( $quote, $id ) = $cleansed_action_piece =~ /^id:(["']?)(\d+)/ ) {
                if ( $opts->{change_id} ) {
                    $id = $opts->{change_id};
                    $line =~ s{id:(["']?)\d+}{id:$quote$id};
                }
                $self->id($id);
            }

            if ( my @msg_match = $cleansed_action_piece =~ m{^msg: (?: '((?:[^']|\\')+)' | "((?:[^"]|\\")+)" | ([^,]+) ) }x ) {
                my ($msg) = grep { defined } @msg_match;
                $self->meta_msg($msg);
            }
        }
    }

    $self->{text} .= $line;

    return \%discovered;
}

=head2 $chunk->text()

=head3 Purpose

R/W accessor for the 'text' attribute. On edit, repopulates chunk attributes
based on what's found in the new rule text.

=head3 Returns

The rule text, which remains the same regardless of whether the chunk
is marked as disabled or not.

=cut

sub text {
    my ( $self, $text ) = @_;
    if ( defined $text ) {
        $self->_init();    # clear attributes
        $self->append($text);
    }
    return $self->{text};
}

=head2 $chunk->text_for_config_file()

=head3 Returns

The rule text as it should appear if written back to a config file.
This function originally took care of disabling via commenting out,
but that functionality has been deprecated. The function is left
in place, to allow for any other edits that might be needed.

=cut

sub text_for_config_file {
    my ($self) = @_;
    my $rule_text = $self->text;

    return $rule_text;
}

=head2 $chunk->staged()

=head3 Purpose

R/W accessor for the 'staged' attribute. No special behavior.

=head3 Returns

A boolean value indicating whether the chunk has staged changes.

=cut

sub staged {
    my ( $self, $state ) = @_;
    if ( defined $state ) {
        $self->{staged} = $state;
    }
    return $self->{staged};
}

=head2 $chunk->disabled()

=head3 Purpose

R/W accessor for the 'disabled' attribute. No special behavior.

=head3 Returns

A boolean value indicating whether the chunk is marked as disabled.

=cut

sub disabled {
    my ( $self, $state ) = @_;
    if ( defined $state ) {
        $self->{disabled} = $state;
    }
    return $self->{disabled};
}

=head2 $chunk->vendor()

=head3 Purpose

R/W accessor for the 'vendor' attribute. No special behavior.

This information may be used to dictate whether the rule being disabled should impact the
rule text or not.

=head3 Returns

A boolean value indicating whether the chunk is marked as a vendor rule.

=cut

sub vendor {
    my ( $self, $state ) = @_;
    if ( defined $state ) {
        $self->{vendor} = $state;
    }
    return $self->{vendor};
}

=head2 $chunk->id()

=head3 Purpose

R/W accessor for the 'id' attribute. No special behavior.

=head3 Returns

The mod_security rule id for this chunk, or empty string if no rule id
is known.

=cut

sub id {
    my ( $self, $id ) = @_;
    if ( defined $id ) {
        $self->{id} = $id;
    }
    return $self->{id};
}

=head2 $chunk->meta_msg()

=head3 Purpose

R/W accessor for the 'meta_msg' attribute (the 'msg' field from the rule metadata). No special behavior.

=head3 Returns

The mod_security rule msg for this chunk, or empty string if no rule msg was found in the metadata when
parsing the rule.

=cut

sub meta_msg {
    my ( $self, $msg ) = @_;
    if ( defined $msg ) {
        $self->{meta_msg} = $msg;
    }
    return $self->{meta_msg};
}

=head2 $chunk->export()

=head3 Purpose

When a mass operation is being performed on chunks, transform the chunk as the caller
requested when constructing the object.

=head3 Returns

Either a hash ref representing the chunk or the chunk object itself. See the constructor
'export_as' parameter.

Hash structure example:

  { id => XXXXXXX, disabled => 1, rule => "SecRule ..........\n" }

=cut

sub export {
    my ($self) = @_;
    if ( $self->{'export_as'} eq 'self' ) {
        return $self;
    }
    elsif ( $self->{'export_as'} eq 'plain' ) {
        return $self->plain;
    }
    else {
        Carp::croak( lh()->maketext( q{The entered value for the [asis,export_as] parameter is not valid: [_1]}, $self->{'export_as'} ) );
    }
}

sub plain {
    my ($self) = @_;
    return {
        id            => $self->id,
        disabled      => $self->{disabled},
        staged        => $self->{staged},
        rule          => $self->{text},
        meta_msg      => $self->meta_msg,
        config        => $self->config,
        vendor_id     => $self->vendor_id,
        config_active => $self->config_active,
        vendor_active => $self->vendor_active,
    };

}

=head2 $chunk->empty()

Returns a boolean value indicating whether the chunk is empty. A chunk is understood to be non-empty
if it contains at least one non-whitespace character.

=cut

sub empty {
    my ($self) = @_;
    return $self->text !~ /\S/;
}

=head2 $chunk->punctuate()

Decides for the caller how to correctly set other chunks apart from this chunk. After the caller
writes $chunk->text_for_config_file() to a file, it should also write $chunk->punctuate() unless
the spacing doesn't matter.

=cut

sub punctuate {
    my ($self) = @_;
    return "\n" if $self->{text}                 =~ m{^\s*(?:SecRule|SecAction|\#)}m;
    return ''   if $self->empty || $self->{text} =~ /\n\z/;
    return "\n";
}

=head2 $chunk->is_include()

Returns a true value if this chunk is an Include directive; false otherwise

=cut

sub is_include {
    my ($self) = @_;
    return $self->{text} =~ m{^\s*Include\s};
}

=head2 $chunk->config()

Returns a string (or empty string if unknown) indicating which configuration file (relative path)
this chunk came from.

=cut

sub config {
    my ($self) = @_;
    return $self->{config} || '';
}

=head2 $chunk->vendor_id()

Returns a string (or empty string if not applicable) indicating which vendor_id this rule belongs to.

=cut

sub vendor_id {
    my ($self) = @_;
    return Whostmgr::ModSecurity::extract_vendor_id_from_config_name( $self->config ) || '';
}

sub config_active {
    my ( $self, $set ) = @_;
    if ( defined $set ) {
        $self->{config_active} = $set;
    }
    elsif ( Whostmgr::ModSecurity::relative_modsec_user_conf() eq $self->config ) {
        $self->{config_active} = 1;
    }

    if ( defined( $self->{config_active} ) && length( $self->{config_active} ) ) {
        return $self->{config_active};
    }

    my $active_configs = Whostmgr::ModSecurity::ModsecCpanelConf->new->active_configs;
    return ( $active_configs->{ $self->config } ? 1 : 0 );
}

sub vendor_active {
    my ( $self, $set ) = @_;
    if ( defined $set ) {
        $self->{vendor_active} = $set;
    }
    elsif ( Whostmgr::ModSecurity::relative_modsec_user_conf() eq $self->config ) {
        $self->{vendor_active} = 1;
    }

    if ( defined( $self->{vendor_active} ) && length( $self->{vendor_active} ) ) {
        return $self->{vendor_active};
    }

    my $active_vendors = Whostmgr::ModSecurity::ModsecCpanelConf->new->active_vendors;
    return ( $active_vendors->{ $self->vendor_id } ? 1 : 0 );
}

sub assign_new_unique_id {
    my ($self) = @_;
    my $text = $self->text;

    my $result   = Whostmgr::ModSecurity::Parse::get_chunk_objs( Whostmgr::ModSecurity::get_safe_config_filename( Whostmgr::ModSecurity::modsec_user_conf() ) );
    my %used_ids = map { $_->id => 1 } grep { $_->id } @{ $result->{chunks} };
    my $validation_errors;
    for my $new_id ( Whostmgr::ModSecurity::custom_rule_id_range_start() .. Whostmgr::ModSecurity::custom_rule_id_range_end() ) {
        if ( !$used_ids{$new_id} ) {
            $self->_init();
            $self->append( $text, { change_id => $new_id } );

            # Even though we already believe that this id is available, go ahead and verify that
            # adding the rule with this id will work. The validation could theoretically fail due
            # to the directive syntax being invalid, but what we're actually concerned about here
            # is that the next available id in the custom rule range might actually be occupied
            # by a rule in something other than modsec2.user.conf. Regardless of the cause, if this
            # validation fails more than a handful of times, we should give up, because the validation
            # operation is too expensive to repeat across the entire custom rule id range.
            if ( eval { Whostmgr::ModSecurity::validate_rule( $self->text ) } ) {
                return 1;
            }
            elsif ( ++$validation_errors > 9 ) {
                die lh()->maketext( 'A validation error occurred in the attempt to find a new ID for the rule: [_1]', Cpanel::Exception::to_string($@) ) . "\n" . "rule text was: " . $self->text;
            }
        }
    }
    die lh()->maketext('The system could not find an available ID to use for the rule. All IDs in the designated range (1 - 99,999) are already in use.') . "\n";
}

sub _parse_rule {
    my ($line) = @_;
    $line =~ s/[\015\012]$//g;
    if (
        $line =~ m{^\s* SecRule
                         [\s\n\\]+
                         (\S+)                             # VARIABLES
                         [\s\n\\]+
                         (?: ([^"']\S+) | "((?:\\"|[^"])+)" | '((?:\\'|[^'])+)' ) # OPERATOR (unquoted, double-quoted, or single-quoted)
                         (?:
                             [\s\n\\]+
                             (?: ([^"']\S+) | "((?:\\"|[^"])+)" | '((?:\\'|[^'])+)' ) # [ACTIONS]
                         )?
                   }xms
    ) {
        return $1,           # VARIABLES
          $2 || $3 || $4,    # OPERATOR
          $5 || $6 || $7;    # [ACTIONS]
    }
    elsif (
        $line =~ m{^\s* SecAction
                        [\s\n\\]+
                        (?: ([^"']\S+) | "((?:\\"|[^"])+)" | '((?:\\'|[^'])+)' ) # ACTIONS
                  }xms
    ) {
        # VARIABLES, OPERATOR, ACTIONS
        return undef, undef, $1 || $2 || $3;
    }

    return;
}

# For use in unit tests
sub debug {
    my ($self) = @_;
    return [ map { [ _parse_rule($_) ] } split /\n\n/, $self->text ];
}

1;
