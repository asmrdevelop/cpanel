package Cpanel::Locale::Utils::XLIFF;

# cpanel - Cpanel/Locale/Utils/XLIFF.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Encode                                        ();
use Cpanel::CPAN::Locales                         ();
use XML::Writer                                   ();
use XML::Parser                                   ();
use Cpanel::CPAN::Locale::Maketext::Utils::Phrase ();
use Cpanel::Hash                                  ();
use Cpanel::YAML::Syck                            ();

# This hash contains the names of extended methods that cPanel supplies in addition
# to the ones in Cpanel::CPAN::Locale::Maketext::Utils::Phrase. If we provide more, update this
# hash to include them as well.
my %cpanel_functions = map { $_ => 'meth' } qw/get_locale_name get_locale_name_or_nothing get_user_locale_name local_datetime/;

my $bn_var_regexp = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::get_bn_var_regexp();

sub new {
    my ( $class, $output, $options ) = @_;
    $output ||= '';

    my $xml_writer = XML::Writer->new(
        'OUTPUT'    => ( $output eq '' ? \$output : $output ),
        'ENCODING'  => 'utf-8',
        'NEWLINES'  => 0,
        'DATA_MODE' => 0,
        'UNSAFE'    => 1,
    );
    binmode $output if $output ne '';    # Work around for rt 77363

    my $xml_parser = XML::Parser->new(
        'Style'            => 'Objects',
        'ProtocolEncoding' => 'UTF-8',
    );

    # Avoid loading external files.
    $xml_parser->setHandlers( 'ExternEnt' => sub { undef } );

    my $non_translatable_type_regexp = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::get_non_translatable_type_regexp();

    # TODO: ? set via new() args ?
    my $src_loc = Cpanel::CPAN::Locales->new();
    my $trg_loc = $src_loc;

    return bless {
        'id_counter'                   => 0,
        'xml_writer'                   => $xml_writer,
        'xml_writer_output'            => ( $output eq '' ? \$output : $output ),
        'xml_parser'                   => $xml_parser,
        'non_translatable_type_regexp' => $non_translatable_type_regexp,
        'bn_var_regexp'                => $bn_var_regexp,
        'src_loc'                      => $src_loc,
        'trg_loc'                      => $trg_loc,
        'recover'                      => $options->{'recover'},
    }, $class;
}

sub indent {
    my ( $self, $level ) = @_;

    $self->{'xml_writer'}->characters( "\n" . ( "  " x $level ) );
    return;
}

sub _generate_locale_object {
    my ( $self, $target, @candidates ) = @_;

    foreach my $locale ( $target, @candidates ) {
        my $obj = eval { Cpanel::CPAN::Locales->new($locale) };
        return $obj if defined $obj;
    }
    die "Could not make object for target-language ($target): $@";
}

sub generate_xliff_doc_for_phrases {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, @phrases ) = @_;

    if ( $self->xml_is_in_scalar() ) {
        ${ $self->{'xml_writer_output'} } = '';
    }

    my $conf_hr = {};
    if ( ref( $phrases[-1] ) eq 'HASH' ) {
        $conf_hr = pop @phrases;
    }
    die "target-language needs specified" if !$conf_hr->{'target-language'};

    my $yaml               = ( index( $conf_hr->{'target-language'}, 'i_' ) == 0 ) ? YAML::Syck::LoadFile("/var/cpanel/i_locales/$conf_hr->{'target-language'}.yaml") : {};
    my $target_cldr_locale = ( index( $conf_hr->{'target-language'}, 'i_' ) == 0 ) ? $yaml->{'fallback_locale'} || 'en'                                               : $conf_hr->{'target-language'};

    $conf_hr->{'datatype'} ||= 'plaintext';

    $self->{'xml_writer'}->xmlDecl();
    $self->{'xml_writer'}->startTag(
        'xliff',
        'version'  => '1.2',
        'xmlns'    => 'urn:oasis:names:tc:xliff:document:1.2',
        'xmlns:cp' => 'tag:cpanel.net,2012-01:translate',
    );
    $self->indent(1);

    $self->{'xml_writer'}->startTag(
        'file',
        'datatype'        => $conf_hr->{'datatype'},
        'original'        => $conf_hr->{'original'}        || 'original file info not available',
        'source-language' => $conf_hr->{'source-language'} || 'en-US',
        'target-language' => $conf_hr->{'target-language'},
    );
    $self->indent(2);
    local $self->{'src_loc'} = Cpanel::CPAN::Locales->new( $conf_hr->{'source-language'} || 'en-US' ) || die "Could not make object for source-language ($conf_hr->{'source-language'}): $@";
    local $self->{'trg_loc'} = $self->_generate_locale_object( $conf_hr->{'target-language'}, $yaml->{'fallback_locale'}, 'en-US' );

    $self->{'xml_writer'}->startTag('body');

    for my $item (@phrases) {
        if ( index( $item, '__' ) == 0 ) {
            warn "Keys that start with multiple underscores are for special use and will not be included in the XLIFF.";
            next;
        }

        my $phrase = exists $conf_hr->{'arbitrary_key_mapping'}{$item} ? $conf_hr->{'arbitrary_key_mapping'}{$item} : $item;
        ++$self->{'id_counter'};
        $self->indent(3);

        my $id_from_phrase = Cpanel::Hash::get_fastest_hash($phrase);

        $self->{'xml_writer'}->startTag( 'trans-unit', 'datatype' => $conf_hr->{'datatype'}, id => "tu-$id_from_phrase" );
        $self->indent(4);

        if ( $phrase ne $item ) {
            $self->{'xml_writer'}->startTag( 'source', 'cp:lexicon-key' => $item );
        }
        else {
            $self->{'xml_writer'}->startTag('source');
        }

        my $target_phrase = $conf_hr->{'target_map'} && $conf_hr->{'target_map'}{$phrase} // '';

        # Is this phrase an English phrase that we're using only because there's
        # no translation?
        local $self->{'untranslated'} = $phrase eq $target_phrase && $conf_hr->{'target-language'} !~ /^en/;

        # undef, empty string, all whitespace, etc are not able to be translated.
        # Additionally, their use likely indicates the use of partial phrases
        #    (e.g. the legacy key EP404Pre has an empty value) or output formatting (See W1756 for more info)
        my $old_id_counter = $self->{'id_counter'};
        $self->phrase2xliff( $phrase =~ m/\S/ ? $phrase : '[comment,this value intentionally left blank]' );
        $self->{'xml_writer'}->endTag('source');

        # The above phrase2xliff call bumps the id_counter as it does the 'first' pass on the phrase.
        # So, we reset the counter to ensure that the second pass will use the proper id values when processing
        # the target values.
        $self->{'id_counter'} = $old_id_counter;

        if ( $conf_hr->{'target_map'} ) {
            $target_phrase = $conf_hr->{'target_map'}{$phrase} || '';
            $self->indent(4);
            if ( $conf_hr->{'target_note'} ) {
                $self->{'xml_writer'}->startTag( 'target', 'cp:meta-note' => $conf_hr->{'target_note'} );
            }
            else {
                $self->{'xml_writer'}->startTag('target');
            }

            # last parameter tells phrase2xliff that we are processing a 'target' string.
            $self->phrase2xliff( $target_phrase, $self->{'phrase2xliff'}, 1 );
            $self->{'xml_writer'}->endTag('target');
            $self->indent(3);
        }
        else {
            $self->indent(3);
        }

        if ( $self->{'phrase2xliff'}{'_post-source'} ) {
            for my $cmd ( @{ $self->{'phrase2xliff'}{'_post-source'} } ) {
                my $method = $cmd->[0];
                $self->{'xml_writer'}->$method( @{ $cmd->[1] } );
            }
        }

        $self->{'xml_writer'}->endTag('trans-unit');

        if ( $self->{'phrase2xliff'}{'_post-trans-unit'} ) {
            my $indent = 3;
            for my $cmd ( @{ $self->{'phrase2xliff'}{'_post-trans-unit'} } ) {
                my $method = $cmd->[0];
                if ( $method eq "startTag" && $cmd->[1][0] =~ /^(?:group|trans-unit)$/ ) {
                    $self->indent( $indent++ );
                }
                elsif ( $method eq "startTag" && $cmd->[1][0] =~ /^(?:source|target|note)$/ ) {

                    # We indent only the start tags for these since otherwise
                    # we'll include extra space into the string to be
                    # translated.
                    $self->indent($indent);
                }
                elsif ( $method eq "endTag" && $cmd->[1][0] =~ /^(?:group|trans-unit)$/ ) {
                    $self->indent( --$indent );
                }
                $self->{'xml_writer'}->$method( @{ $cmd->[1] } );
            }
        }
    }

    $self->indent(2);
    $self->{'xml_writer'}->endTag('body');
    $self->indent(1);
    $self->{'xml_writer'}->endTag('file');
    $self->indent(0);
    $self->{'xml_writer'}->endTag('xliff');
    $self->{'xml_writer'}->end();

    if ( $self->xml_is_in_scalar() ) {
        return $self->get_xml_as_string();
    }
    else {
        $self->{'xml_writer_output'}->close() unless $conf_hr->{'leave_output_open'};
        return 1;
    }
}

sub xml_is_in_scalar {
    my ($node) = @_;
    return 1 if ref( $node->{'xml_writer_output'} ) eq 'XML::Writer::_String';
    return;
}

sub get_xml_as_string {
    my ($node) = @_;
    die "XML is not output to a scalar" unless $node->xml_is_in_scalar();
    return ${ $node->{'xml_writer_output'} };
}

sub phrase2xliff {
    my ( $self, $phrase, $target_mode_phrase2xliff, $processing_target_phrase ) = @_;

    $self->{'phrase2xliff'} = $target_mode_phrase2xliff || {};    # ensure it is fresh each call, like $@ after eval

    my $struct = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::phrase2struct($phrase);

    # include the phrase in phrase2xliff() die() output
    local $SIG{__DIE__} = sub {
        die "There was a problem with:\n\t'$phrase':\n@_";
    };

    for my $piece ( @{$struct} ) {
        ++$self->{'id_counter'};

        if ( !ref($piece) ) {
            $self->{'xml_writer'}->characters($piece);
        }
        else {

            # Convert our extensions to method calls.
            $piece->{'type'} = $cpanel_functions{ $piece->{'list'}[0] } if $piece->{'type'} eq '_unknown' and $cpanel_functions{ $piece->{'list'}[0] };

            die "Unknown BN: “$piece->{'orig'}”" if $piece->{'type'} eq '_unknown';
            die "Invalid BN: “$piece->{'orig'}”" if $piece->{'type'} eq '_invalid';

            if ( $piece->{'type'} =~ m/\A$self->{non_translatable_type_regexp}\z/o ) {
                $self->{'xml_writer'}->startTag( 'ph', 'id' => "bn-$self->{'id_counter'}", 'ctype' => "x-bn-$piece->{'type'}", 'assoc' => 'both' );
                $self->{'xml_writer'}->characters( $piece->{'orig'} );
                $self->{'xml_writer'}->endTag('ph');
            }
            elsif ( $piece->{'type'} eq 'basic' ) {
                $self->_basic_piece_to_xliff( $piece, $target_mode_phrase2xliff );
            }
            elsif ( $piece->{'type'} eq 'complex' ) {
                $self->_complex_piece_to_xliff( $piece, $target_mode_phrase2xliff, $processing_target_phrase );
            }
            else {
                die "How did we get here “$piece->{'type'}”?";
            }
        }
    }

    if ( $self->xml_is_in_scalar() ) {
        return $self->get_xml_as_string();
    }
    else {
        return 1;
    }
}

sub _basic_piece_to_xliff {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, $piece, $target_mode ) = @_;

    my $last_list_id = @{ $piece->{'list'} } - 1;

    my $hash_start_idx = 2;
    if ( $piece->{'list'}[0] eq 'output' && ( $piece->{'list'}[1] eq 'img' || $piece->{'list'}[1] eq 'abbr' || $piece->{'list'}[1] eq 'acronym' || $piece->{'list'}[1] eq 'url' ) ) {
        $hash_start_idx += 2;
    }
    elsif ( $piece->{'list'}[0] eq 'output' || $piece->{'list'}[0] eq 'datetime' ) {    # 'datetime' because only the second argument is able to be translated
        $hash_start_idx += 1;
    }

    # Account for the simple form of output,url
    if ( $piece->{'list'}[1] eq 'url' ) {
        if ( @{ $piece->{'list'} } != 4 ) {                                             # do not go into has start index logic when it is [output,url,_1,xyz]
            if ( @{ $piece->{'list'} } == 3 ) {
                --$hash_start_idx;
            }
            elsif ( ( -1 == index( $piece->{'list'}[3], ' ' ) ) ) {                     # cheap hack since attribute keys don't have spaces
                --$hash_start_idx;

                if ( $piece->{'list'}[$last_list_id] =~ m/\A$self->{'bn_var_regexp'}\z/o ) {

                    # output,url,_1,WORD,foo,bar,_2
                    ++$hash_start_idx unless $last_list_id % 2;
                }
                else {

                    # output,url,_1,WORD,foo,bar
                    ++$hash_start_idx if $last_list_id % 2;
                }
            }
            elsif ( $piece->{'list'}[$last_list_id] =~ m/\A$self->{'bn_var_regexp'}\z/o ) {
                --$hash_start_idx if $last_list_id % 2;
            }
            else {
                --$hash_start_idx unless $last_list_id % 2;
            }
        }
    }

    $self->{'xml_writer'}->startTag( 'ph', 'id' => "bn-$self->{'id_counter'}", 'ctype' => "x-bn-$piece->{'type'}", 'assoc' => 'both' );

    # Handle the '2 possibly localizable args before the arbitrary hash' cases
    if ( $hash_start_idx == 4 ) {

        # handle first two args: $hash_start_idx - 2, and $hash_start_idx - 1,
        $self->{'xml_writer'}->characters("[$piece->{'list'}[0],$piece->{'list'}[1],");

        for my $idx ( $hash_start_idx - 2, $hash_start_idx - 1 ) {
            my $trailing_comma = $idx < $last_list_id ? ',' : '';

            if ( defined $piece->{'list'}[$idx] && $piece->{'list'}[$idx] =~ m/\A$self->{'bn_var_regexp'}\z/o ) {
                $self->{'xml_writer'}->characters( $piece->{'list'}[$idx] . $trailing_comma );
                next;
            }

            $self->{'xml_writer'}->startTag('sub');
            $self->_process_data_with_embedded_bn_var( $self->{'id_counter'}, $self->{'xml_writer'}, $piece->{'list'}[$idx], $idx );
            $self->{'xml_writer'}->endTag('sub');
            $self->{'xml_writer'}->characters(',') if $trailing_comma;
        }
    }
    else {

        # handle first arg: $hash_start_idx - 1
        my $idx = $hash_start_idx - 1;
        $self->{'xml_writer'}->characters( '[' . join( ',', @{ $piece->{'list'} }[ 0 .. $hash_start_idx - 2 ] ) );

        my $trailing_comma = $idx < $last_list_id ? ',' : '';

        if ( defined $piece->{'list'}[$idx] && $piece->{'list'}[$idx] =~ m/\A$self->{'bn_var_regexp'}\z/o ) {
            $self->{'xml_writer'}->characters( ',' . $piece->{'list'}[$idx] . $trailing_comma );
        }
        else {
            $self->{'xml_writer'}->characters(',');
            $self->{'xml_writer'}->startTag('sub');
            $self->_process_data_with_embedded_bn_var( $self->{'id_counter'}, $self->{'xml_writer'}, $piece->{'list'}[$idx], $idx );
            $self->{'xml_writer'}->endTag('sub');
            $self->{'xml_writer'}->characters(',') if $trailing_comma;
        }
    }

    # 'datetime' does not support the arbitrary hash so no need to process it.
    # Also no need to process the arbitrary hash if there is no data to process.
    if ( $piece->{'list'}[0] ne 'datetime' && $last_list_id >= $hash_start_idx ) {
        my %attr = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::_get_attr_hash_from_list( $piece->{'list'}, $hash_start_idx );

        # Since we do not have access to the arguments we can not tell if a trailing variable is a string of a hashref (like we can at runtime)
        # That is not normally a problem except under one circumstance which we want to warn about and move on instead of die()ing
        if ( !$target_mode && $piece->{'list'}[0] eq 'output' && $piece->{'list'}[1] eq 'url' && $piece->{'list'}[-1] =~ m/\A$self->{'bn_var_regexp'}\z/o && @{ $piece->{'list'} } > 4 ) {
            warn "Possible ambiguous use of trailing variable in output,url: $piece->{'orig'}\n" if !$ENV{TAP_VERSION} && !$INC{"Test/More.pm"};
        }

        # We have more arguments so process %attr and rebuild
        for my $idx ( $hash_start_idx .. $last_list_id ) {
            my $trailing_comma = $idx < $last_list_id ? ',' : '';

            if (
                $idx == $hash_start_idx                                                                                   # the first thing will never be localizable, it will be a key or an arbitrary hashref var, this also keeps the - 1 index check below from erroneously matching
                || $piece->{'list'}[$idx] =~ m/\A$self->{'bn_var_regexp'}\z/o                                             # a variable ref is not localizable
                || ( $piece->{'list'}[1] eq 'url' && $piece->{'list'}[ $idx - 1 ] !~ m/\A(?:title|alt|html|plain)\z/ )    # url has 2 special text keys
                || ( $piece->{'list'}[1] ne 'url' && $piece->{'list'}[ $idx - 1 ] !~ m/\A(?:title|alt)\z/ )               # only 'alt' and 'title' values are localizable

            ) {
                $self->{'xml_writer'}->characters( $piece->{'list'}[$idx] . $trailing_comma );
            }
            else {
                if (   $piece->{'list'}[ $idx - 1 ] eq 'title' && exists $attr{'title'} && $attr{'title'} ne $piece->{'list'}[$idx]
                    || $piece->{'list'}[ $idx - 1 ] eq 'alt' && exists $attr{'alt'} && $attr{'alt'} ne $piece->{'list'}[$idx] ) {
                    die "title/alt mismatch (mutliple title/alt attributes?)";
                }

                $self->{'xml_writer'}->startTag('sub');
                $self->_process_data_with_embedded_bn_var( $self->{'id_counter'}, $self->{'xml_writer'}, $piece->{'list'}[$idx], $idx );
                $self->{'xml_writer'}->endTag('sub');
                $self->{'xml_writer'}->characters(',') if $trailing_comma;
            }
        }
    }

    $self->{'xml_writer'}->characters(']');
    $self->{'xml_writer'}->endTag('ph');
    return;
}

sub _complex_piece_to_xliff {
    my ( $self, $piece, $merge_target_post, $processing_target_phrase ) = @_;

    my $identifer_tag = join( ',', $piece->{'list'}[0] // '', $piece->{'list'}[1] // '' );
    my $piece_uniq    = @{ $piece->{'list'} } >= 2 ? "1-$identifer_tag" : $piece->{'list'}[0];

    my $piece_num = 1;
    if ( !$processing_target_phrase ) {

        # If we are processing a 'source' phrase, then we must account for multiple quant/numerate fields.
        #
        # We do this, by creating an 'unique' id for each numerate and quant in the phrase.
        # This will allow us to properly process phrases with multiple numerate and quant fields,
        # by ensuring that each quant/numerate is processed as a separate group.
        while ( exists $self->{'phrase2xliff'}{'_'}{$piece_uniq} ) {
            $piece_uniq = ++$piece_num . "-$identifer_tag";
        }
    }
    else {
        # If we are processing a 'target' pharse, then we must track which quant or numerate field we are
        # processing by using a 'hidden' counter.
        #
        # NOTE: THIS MEANS THAT THE quant/numerate FIELDS IN THE TARGET PHRASES MUST BE IN THE SAME ORDER
        # AS THE SOURCE PHRASE.
        #
        # There is no reasonable way to account for multiple quant/numerate fields otherwise!
        $piece_uniq = ++$self->{'phrase2xliff'}->{ 'target_piece_num_for_' . $identifer_tag } . "-$identifer_tag";
    }

    # handle *, ick
    die "quant() alias * not allowed" if $piece->{'list'}[0] eq '*';

    # handle quant and numerate
    if ( $piece->{'list'}[0] eq 'quant' || $piece->{'list'}[0] eq 'numerate' ) {
        my $last_idx = @{ $piece->{'list'} } - 1;
        my @src_args = @{ $piece->{'list'} }[ 2 .. $last_idx ];

        ++$self->{'id_counter'};
        $self->{'phrase2xliff'}{'_'}{$piece_uniq}{'cp:ref'} //= "gp-$self->{'id_counter'}";

        $self->{'xml_writer'}->startTag(
            'ph',
            'id'         => "bn-$self->{'id_counter'}",
            'ctype'      => "x-bn-$piece->{'type'}",
            'assoc'      => 'both',
            'cp:replace' => $piece->{'orig'},
            'cp:ref'     => $self->{'phrase2xliff'}{'_'}{$piece_uniq}{'cp:ref'},
        );
        $self->{'xml_writer'}->characters( $piece->{'orig'} );
        $self->{'xml_writer'}->endTag('ph');

        if ($merge_target_post) {

            # call as function to further indicate this is internal only
            __get_quant_numerate_group_contents_arrayrefs( $self, $piece->{'list'}, $piece_uniq, $merge_target_post );
        }
        else {
            push @{ $self->{'phrase2xliff'}{'_post-trans-unit'} }, (
                [ 'startTag', [ 'group', 'id', "gp-$self->{'id_counter'}" ] ],

                # call as function to further indicate this is internal only
                __get_quant_numerate_group_contents_arrayrefs( $self, $piece->{'list'}, $piece_uniq ),
                [ 'endTag', ['group'] ],
            );
        }
    }

    ### handle bracket notation types: bracket notation types: boolean, is_future, is_defined
    elsif ( $piece->{'list'}[0] eq 'boolean' || $piece->{'list'}[0] eq 'is_future' || $piece->{'list'}[0] eq 'is_defined' ) {

        # index position of arguments in the bracket notation
        my $start_idx = 1;

        if ( defined( $piece->{'list'}[1] ) && $piece->{'list'}[1] =~ m/\A$self->{'bn_var_regexp'}\z/o ) {
            $start_idx += 1;
        }
        else {
            die "\nERROR: Encountered unexpected bracket notation format; only bn var should be used (eg. _1, _2)";
        }

        # Create corresponding <ph> element for the bracket notation
        $self->{'xml_writer'}->startTag( 'ph', 'id' => "bn-$self->{'id_counter'}", 'ctype' => "x-bn-$piece->{'type'}", 'assoc' => 'both' );

        # Create data for the first two args of the bracket notation
        $self->{'xml_writer'}->characters("[$piece->{'list'}[0],$piece->{'list'}[1],");

        # Create data for the remaining arguments of the bracket notation
        my $bn_field_count = $piece->{'cont'} =~ tr/,//;

        my $trailing_comma = undef;
        my $efcount        = 0;
        for my $idx ( $start_idx .. $bn_field_count ) {
            $trailing_comma = $idx < $bn_field_count ? ',' : '';

            $self->{'xml_writer'}->startTag('sub');

            if ( defined( $piece->{'list'}[$idx] ) && length( $piece->{'list'}[$idx] ) > 0 ) {
                $self->_process_data_with_embedded_bn_var( $self->{'id_counter'}, $self->{'xml_writer'}, $piece->{'list'}[$idx], $idx );
            }
            else {
                $efcount++;
                $self->{'xml_writer'}->startTag( 'ph', 'id' => "bn-$self->{'id_counter'}-$idx-emptyfield-$efcount", 'ctype' => "x-bn-empty-field", 'assoc' => 'both' );
                $self->{'xml_writer'}->endTag('ph');
            }

            $self->{'xml_writer'}->endTag('sub');
            $self->{'xml_writer'}->characters(',') if $trailing_comma;
        }

        # Close element
        $self->{'xml_writer'}->characters(']');
        $self->{'xml_writer'}->endTag('ph');

    }
    ###

    # handle specific 'complex' $piece->{'list'}[0] here:
    # elsif () {}

    else {
        die "I do not know how to handle the “complex” type method “$piece->{'list'}[0]”";
    }
    return;
}

sub xliff2phrase {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, $xml, $id_lookup ) = @_;
    $id_lookup ||= {};    # id=>[XML::Parser=>parse() tree]
    die "reference data must be in a hashref" if ref($id_lookup) ne 'HASH';

    # use $self->{'xml_parser'} to build $struct out of $xml
    my $tree;
    if ( ref($xml) ) {
        die "Objects passed to xliff2phrase() must be a <source> or <target> object" if ref($xml) !~ m/::(?:source|target)$/;
        $tree = [$xml];
    }
    else {
        $tree = $self->{'xml_parser'}->parse("<struct>$xml</struct>");
    }

    my @struct;

    die "Given structure does not have a Kids data." if !exists $tree->[0]{'Kids'};

    for my $piece ( @{ $tree->[0]{'Kids'} } ) {
        if ( ref($piece) =~ m/::Characters$/ ) {
            push @struct, Encode::encode_utf8( $piece->{'Text'} );    # encode_utf8() will turn the XML’s wide–character Unicode string into a utf-8 byte string
        }
        else {

            # if <source> or <target> ever contain anything other than <ph> then this will need adjusted/moved accordingly
            die "Given structure contains tags other than <ph>" if ref($piece) !~ m/::ph$/;

            my $type = $piece->{'ctype'};
            $type =~ s/^x-bn-//;

            my $orig;

            die "Unknown BN" if $type eq '_unknown';
            die "Invalid BN" if $type eq '_invalid';

            if ( $type =~ m/\A$self->{non_translatable_type_regexp}\z/o ) {
                $orig = $piece->{Kids}[0]{'Text'};
            }
            elsif ( $type eq 'basic' ) {
                $orig = __get_string_from_kids($piece);
            }
            elsif ( $type eq 'complex' ) {
                my $orig_text = __get_string_from_kids($piece);

                my $bn_struct = @{ Cpanel::CPAN::Locale::Maketext::Utils::Phrase::phrase2struct($orig_text) }[0];

                ## handle *, ick
                die "quant() alias * not allowed" if $bn_struct->{'list'}[0] eq '*';

                # handle quant and numerate
                if ( $bn_struct->{'list'}[0] eq 'quant' || $bn_struct->{'list'}[0] eq 'numerate' ) {
                    $orig = "[$bn_struct->{'list'}[0],$bn_struct->{'list'}[1]";
                    die "cp:ref value does not match content"                     if $piece->{'cp:replace'} ne $bn_struct->{'orig'};    # simple sanity check, won't catch if they edited both strings the same way
                    die "reference data does not include id “$piece->{'cp:ref'}”" if !exists $id_lookup->{ $piece->{'cp:ref'} };

                  TRANS_UNIT:
                    for my $tu ( @{ $id_lookup->{ $piece->{'cp:ref'} }[0]{'Kids'} } ) {
                        next if ref($tu) !~ m/::trans-unit$/;

                        my $started_type;

                      SRC_TRG:

                        # sort() allows us to find target before source when both exist
                        for my $txt ( sort { ref($b) cmp ref($a) } @{ $tu->{'Kids'} } ) {
                            next SRC_TRG unless ref($txt) =~ m/::(source|target)$/;
                            my $txt_type = $1;
                            $started_type ||= $txt_type;
                            next SRC_TRG if $started_type ne $txt_type;    # target ended before source: source has spec zero, target does not

                            next SRC_TRG if exists $txt->{'cp:ref'} && $txt->{'cp:ref'} eq 'do_not_factor_into_lex';
                            next SRC_TRG if $txt_type eq 'target'   && !@{ $txt->{'Kids'} };                           # Ignore empty target tag

                            my $res        = '';
                            my $idx        = -1;
                            my $is_implied = 0;
                          CHUNK:
                            for my $prt ( @{ $txt->{'Kids'} } ) {
                                $idx++;
                                if ( exists $prt->{'ctype'} && $prt->{'ctype'} eq 'x-implied' ) {
                                    $is_implied = 1;
                                    next CHUNK;    # leave out implied '%s '
                                }

                                my $chrs = '';
                                if ( exists $prt->{'Text'} ) {

                                    # probably not needed but just in case the XML structure changes to an empty item in Kids instead of an empty Kids
                                    next SRC_TRG if $txt_type eq 'target' && $prt->{'Text'} =~ /\A\s+\z/;    # Ignore empty target tag
                                    $chrs = $prt->{'Text'};
                                }
                                elsif ( $prt->{'Kids'}[0]{'Text'} ) {
                                    $chrs = $prt->{'Kids'}[0]{'Text'};
                                }
                                else {
                                    die "Can not find 'Text'";
                                }

                                if ( $is_implied && $idx == 1 ) {
                                    $chrs =~ s/^ //;                                                         # leave out implied '%s '
                                }

                                $res .= $chrs;

                            }

                            $orig .= ",$res";

                            last SRC_TRG;    # only do the first one we find via sort() && next()
                        }
                    }

                    $orig .= ']';

                }
                elsif ( $bn_struct->{'list'}[0] eq 'boolean' || $bn_struct->{'list'}[0] eq 'is_future' || $bn_struct->{'list'}[0] eq 'is_defined' ) {
                    $orig .= __get_string_from_kids($piece);
                }

                # handle specific 'complex' $bn_struct->{'list'}[0] here:
                # elsif () {}

                else {
                    die "I do not know how to handle “complex” type method “$bn_struct->{'list'}[0]”";
                }
            }
            else {
                die "How did we get here “$type”?";
            }

            $orig = Encode::encode_utf8($orig);    # encode_utf8() will turn the XML’s wide–character Unicode string into a utf-8 byte string

            my $cont = $orig;
            $cont =~ s/^\[//;
            $cont =~ s/\]$//;
            my $list = [ Cpanel::CPAN::Locale::Maketext::Utils::Phrase::_split_bn_cont($cont) ];

            push @struct,
              {
                'orig' => $orig,
                'cont' => $cont,
                'list' => $list,
                'type' => $type,
              };
        }
    }

    my $phrase = Cpanel::CPAN::Locale::Maketext::Utils::Phrase::struct2phrase( \@struct );
    $phrase =~ s/\A\s+//g unless $phrase =~ m/^\s…/;    # Don't strip whitespace when followed by ellipis.
    $phrase =~ s/\s+\z//g;                              # When available use L::M::U::__WS() instead.
    return $phrase;
}

sub __get_idx_of_next_end_source {
    my ( $group_ar, $current_idx, $min, $max ) = @_;
    $current_idx ||= 0;
    return $current_idx if $current_idx >= $max;

    for my $idx ( $current_idx + 1 .. $max ) {
        if ( $group_ar->[$idx][0] eq 'endTag' && $group_ar->[$idx][1][0] eq 'source' ) {
            $current_idx = $idx;
            last;
        }
    }

    return $current_idx + 1 if $current_idx < $max;
    return $current_idx;
}

sub __get_quant_numerate_group_contents_arrayrefs {    ## no critic(ProhibitExcessComplexity) -- needs improved tests before refactor
    my ( $self, $bn_list, $piece_uniq, $merge_target_post ) = @_;

    my $merge_target_post_idx;
    my $merge_target_post_min;
    my $merge_target_post_max;

    if ( $merge_target_post->{'_post-trans-unit'} ) {
        my ( $group_start, $group_end );
        my $last_idx = @{ $merge_target_post->{'_post-trans-unit'} } - 1;

        for my $idx ( 0 .. $last_idx ) {
            my $chunk = $merge_target_post->{'_post-trans-unit'}[$idx];

            if ( $chunk->[0] eq 'startTag' && $chunk->[1][0] eq 'group' && $chunk->[1][1] eq 'id' && $chunk->[1][2] eq $self->{'phrase2xliff'}{'_'}{$piece_uniq}{'cp:ref'} ) {
                $group_start = $idx;
            }

            if ( defined $group_start && $chunk->[0] eq 'endTag' && $chunk->[1][0] eq 'group' ) {
                $group_end = $idx;
                last;
            }
        }

        die "Could not determine group data slice points\n" if !defined $group_start || !defined $group_end;

        $merge_target_post_idx = $group_start;
        $merge_target_post_min = $group_start;
        $merge_target_post_max = $group_end;
    }

    my $last_idx = @{$bn_list} - 1;
    my @src_args = @{$bn_list}[ 2 .. $last_idx ];

    my @arrary_refs;    # push @arrary_refs, [ 'xml_writer_method', [qw(method args here)] ];
    my $type_implies_number = $bn_list->[0] eq 'numerate' ? 0 : 1;

    my @plural_cats           = $self->{'trg_loc'}->get_plural_form_categories();
    my $src_arg_cnt           = ( $self->{'src_loc'}->get_plural_form_categories() ) || 2;    # see rt 77404
    my $src_does_spec_zero    = $self->{'src_loc'}->get_plural_form(0) eq 'other' ? 1 : 0;    # see rt 77404
    my $trg_does_special_zero = $self->{'trg_loc'}->get_plural_form(0) eq 'other' ? 1 : 0;    # see rt 77404;

    my $spec_zero_text       = '';
    my $args_do_special_zero = 0;
    if ( $merge_target_post->{'_post-trans-unit'} ) {
        if ( $trg_does_special_zero && _check_if_args_spec_zero( $self->{'phrase2xliff'}{'_'}, $piece_uniq ) ) {
            $args_do_special_zero = 1;
            $spec_zero_text       = pop(@src_args);
        }

        # If this is an English phrase we're using because there is no
        # translation, then it's okay if the number of plural categories is
        # wrong.
        if ( @src_args != @plural_cats && !$self->{'untranslated'} ) {
            my $args_cnt = @src_args;
            my $cats_cnt = @plural_cats;
            my $chunk    = '[' . join( ',', @{$bn_list} ) . ']';

            # warn since the target can be fixed
            warn "The number of arguments to quant ($args_cnt in $chunk) is incorrect (should be $cats_cnt for $self->{'trg_loc'}{'locale'}).\n" if !$ENV{TAP_VERSION} && !$INC{"Test/More.pm"};
        }
    }
    else {
        if ( $src_does_spec_zero && @src_args == $src_arg_cnt + 1 ) {
            $self->{'phrase2xliff'}{'_'}{$piece_uniq}{'src_args_spec_zero'} = 1;
            $args_do_special_zero                                           = 1;
            $spec_zero_text                                                 = pop(@src_args);
        }

        if ( @src_args != $src_arg_cnt ) {
            die "args to quant is weird (src)";    # die since source is wrong
        }
    }

    my $starting_len = $merge_target_post->{'_post-trans-unit'} ? @{ $merge_target_post->{'_post-trans-unit'} } : 0;
    for my $idx ( 0 .. $#plural_cats ) {

        # When target has more plural cats than source we mark the extra source tags as ignorable
        my @src_attr = $idx + 1 > $src_arg_cnt && @plural_cats > $src_arg_cnt && !$merge_target_post->{'_post-trans-unit'} ? ( 'cp:ref', 'do_not_factor_into_lex', 'cp:meta-note', 'this value is included for completeness' ) : ();

        my $current_len = $merge_target_post->{'_post-trans-unit'} ? @{ $merge_target_post->{'_post-trans-unit'} } : 0;
        $merge_target_post_max += $current_len - $starting_len;
        $starting_len = $current_len;

        my $text = ( $idx > $#src_args ? $src_args[-1] : $src_args[$idx] ) // '';

        if ( $merge_target_post->{'_post-trans-unit'} ) {
            $merge_target_post_idx = __get_idx_of_next_end_source( $merge_target_post->{'_post-trans-unit'}, $merge_target_post_idx, $merge_target_post_min, $merge_target_post_max );
            splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'startTag', ['target'] ] );
            $merge_target_post_idx++;
        }
        else {
            push @arrary_refs, [ 'startTag', [ 'trans-unit', 'id', "bn-$self->{'id_counter'}-$plural_cats[$idx]", 'datatype', 'plaintext' ] ];
            push @arrary_refs, [ 'startTag', [ 'source', @src_attr ] ];
        }

        if ( $type_implies_number && $text !~ m/%s/ ) {

            # explicitly have %s when it is implied
            if ( $merge_target_post->{'_post-trans-unit'} ) {
                splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'startTag', [ 'ph', 'id', "num-str-$self->{id_counter}-$plural_cats[$idx]", 'ctype', 'x-implied' ] ], [ 'characters', ['%s'] ], [ 'endTag', ['ph'] ], [ 'characters', [' '] ] );
                $merge_target_post_idx += 4;
            }
            else {
                push @arrary_refs, [ 'startTag', [ 'ph', 'id', "num-str-$self->{id_counter}-$plural_cats[$idx]", 'ctype', 'x-implied' ] ], [ 'characters', ['%s'] ], [ 'endTag', ['ph'] ], [ 'characters', [' '] ];
            }
        }

        my @parts = split( /(\%s)/, $text );
        my $s_id  = -1;
        for my $part (@parts) {
            if ( $part ne '%s' ) {
                if ( $merge_target_post->{'_post-trans-unit'} ) {
                    splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'characters', [$part] ] );
                    $merge_target_post_idx++;
                }
                else {
                    push @arrary_refs, [ 'characters', [$part] ];
                }
            }
            else {
                $s_id++;    # odd but possible to have %s, this ensures the id remain unique under that circumstanc
                if ( $merge_target_post->{'_post-trans-unit'} ) {
                    splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'startTag', [ 'ph', 'id', "num-str-$self->{id_counter}-$s_id-$plural_cats[$idx]", 'ctype', 'x-explicit' ] ], [ 'characters', ['%s'] ], [ 'endTag', ['ph'] ] );
                    $merge_target_post_idx += 3;
                }
                else {
                    push @arrary_refs, [ 'startTag', [ 'ph', 'id', "num-str-$self->{id_counter}-$s_id-$plural_cats[$idx]", 'ctype', 'x-explicit' ] ], [ 'characters', ['%s'] ], [ 'endTag', ['ph'] ];
                }
            }
        }

        if ( $merge_target_post->{'_post-trans-unit'} ) {
            splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'endTag', ['target'] ] );
            $merge_target_post_idx++;
        }
        else {
            push @arrary_refs, [ 'endTag',   ['source'] ];
            push @arrary_refs, [ 'startTag', ['note'] ], [ 'characters', ["Plural category: $plural_cats[$idx]"] ], [ 'endTag', ['note'] ];
            push @arrary_refs, [ 'endTag',   ['trans-unit'] ];
        }
    }

    if ( ( $args_do_special_zero || _check_if_args_spec_zero( $self->{'phrase2xliff'}{'_'}, $piece_uniq ) ) && $src_does_spec_zero ) {

        my $current_len = $merge_target_post->{'_post-trans-unit'} ? @{ $merge_target_post->{'_post-trans-unit'} } : 0;
        $merge_target_post_max += $current_len - $starting_len;
        $starting_len = $current_len;
        if ( $merge_target_post->{'_post-trans-unit'} ) {
            my @no_spec_zero_trg = !$trg_does_special_zero ? ( 'cp:ref', 'do_not_factor_into_lex', 'cp:meta-note', 'this value intentionally left blank' ) : ();
            $merge_target_post_idx = __get_idx_of_next_end_source( $merge_target_post->{'_post-trans-unit'}, $merge_target_post_idx, $merge_target_post_min, $merge_target_post_max );
            splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'startTag', [ 'target', @no_spec_zero_trg ] ] );
            $merge_target_post_idx++;
        }
        else {

            push @arrary_refs, [ 'startTag', [ 'trans-unit', 'id', "bn-$self->{'id_counter'}-special_zero", 'datatype', 'plaintext' ] ];
            push @arrary_refs, [ 'startTag', ['source'] ];
        }

        # Do not fiddle w/ %s for special zero since it is not implied to be prepened like real plural cat args.

        # … however they can explicitly include it.
        my @parts = split( /(\%s)/, $spec_zero_text );
        my $s_id  = -1;
        for my $part (@parts) {
            if ( $part ne '%s' ) {
                if ( $merge_target_post->{'_post-trans-unit'} ) {
                    splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'characters', [$part] ] );
                    $merge_target_post_idx++;
                }
                else {
                    push @arrary_refs, [ 'characters', [$part] ];
                }
            }
            else {
                $s_id++;    # odd but possible to have %s, this ensures the id remain unique under that circumstance
                if ( $merge_target_post->{'_post-trans-unit'} ) {
                    splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'startTag', [ 'ph', 'id', "num-str-$self->{id_counter}-special_zero-target", 'ctype', 'x-implied' ] ], [ 'characters', ['%s'] ], [ 'endTag', ['ph'] ] );
                    $merge_target_post_idx += 3;
                }
                else {
                    push @arrary_refs, [ 'startTag', [ 'ph', 'id', "num-str-$self->{id_counter}-$s_id-special_zero", 'ctype', 'x-explicit' ] ], [ 'characters', ['%s'] ], [ 'endTag', ['ph'] ];
                }
            }
        }
        if ( $merge_target_post->{'_post-trans-unit'} ) {
            splice( @{ $merge_target_post->{'_post-trans-unit'} }, $merge_target_post_idx, 0, [ 'endTag', ['target'] ] );
            $merge_target_post_idx++;
        }
        else {
            push @arrary_refs, [ 'endTag',   ['source'] ];
            push @arrary_refs, [ 'startTag', ['note'] ], [ 'characters', ["Plural category: special_zero"] ], [ 'endTag', ['note'] ];
            push @arrary_refs, [ 'endTag',   ['trans-unit'] ];
        }
    }

    return @arrary_refs;
}

###

sub _process_data_with_embedded_bn_var {
    my ( $self, $id_count, $xml_writer, $data_string, $id_num ) = @_;
    $id_num = defined $id_num ? int($id_num) : 0;

    if ( !defined $data_string || ref $data_string ) {
        my $message = "String data is expected but not detected.";
        die "ERROR: $message" unless $self->{'recover'};
        warn "$message\n" if !$ENV{TAP_VERSION} && !$INC{"Test/More.pm"};
    }

    my $result = undef;

    $result = $data_string;

    my $prior_text = undef;

    my $item         = undef;
    my $text_section = undef;

    my $count = 0;
    while ( defined $data_string && $data_string =~ m/($bn_var_regexp)/og ) {
        $item = $1;
        $count++;

        # Output any data preceding the 'bn_var_regexp' detected
        $text_section = substr( $data_string, 0, index( $data_string, $item ), '' );

        if ($text_section) {
            $xml_writer->characters($text_section);
        }

        # Create data corresponding to the 'bn_var_regexp'
        $xml_writer->startTag( 'ph', 'id' => "bn-$id_count-$id_num-embvar-$count", 'ctype' => "x-bn-embedded-var", 'assoc' => 'both' );
        $xml_writer->characters($item);
        $xml_writer->endTag('ph');

        # Exclude previously processed text
        $text_section = substr( $data_string, 0, index( $data_string, $item ) + length($item), '' );
    }

    # Output remaining data if any
    if ( defined($data_string) ) {
        $xml_writer->characters($data_string);
    }

    return;
}

sub _check_if_args_spec_zero {
    my ( $xliff_data, $piece_tag ) = @_;
    return if !( $xliff_data && ref $xliff_data eq 'HASH' );

    if ( my $id = $xliff_data->{$piece_tag}->{'cp:ref'} ) {
        return 1 if grep { $xliff_data->{$_}->{'cp:ref'} eq $id && $xliff_data->{$_}->{'src_args_spec_zero'} } ( keys %{$xliff_data} );
    }
    return;
}

sub __get_string_from_kids {
    my ($piece) = @_;
    my $string;

    foreach my $p ( @{ $piece->{'Kids'} } ) {
        if ( ref $p eq 'Cpanel::Locale::Utils::XLIFF::Characters' ) {

            # This is the non translated stuff
            $string .= $p->{'Text'};
        }
        elsif ( ref $p eq 'Cpanel::Locale::Utils::XLIFF::sub' ) {
            for my $kid ( @{ $p->{'Kids'} } ) {
                if ( exists $kid->{'Text'} ) {
                    $string .= $kid->{'Text'};
                }
                else {
                    $string .= $kid->{'Kids'}[0]{'Text'} || '';    # the || is for e.g. ctype x-bn-empty-field
                }
            }
        }
    }

    return $string;
}

sub get_target_locale_of_xliff_doc {
    my ( $self, $xliff ) = @_;
    my $ds = $self->{'xml_parser'}->parse($xliff);
    return ( grep { ref($_) =~ m/::file$/ } @{ $ds->[0]{'Kids'} } )[0]{'target-language'};
}

sub get_source_locale_of_xliff_doc {
    my ( $self, $xliff ) = @_;
    my $ds = $self->{'xml_parser'}->parse($xliff);
    return ( grep { ref($_) =~ m/::file$/ } @{ $ds->[0]{'Kids'} } )[0]{'source-language'};
}

sub generate_lexicon_from_xliff_doc {
    my ( $self, $xliff ) = @_;
    my $ds = eval { $self->{'xml_parser'}->parse($xliff) };
    die "Could not parse XLIFF string" if !$ds;

    my $trans_hr = {};

    # When no suitable data is obtained, the process will stop whenever an error is encountered.
    # (This can be adjusted later on depending on how the overall error handling process is expected to work.)

    for my $file_obj ( grep { ref($_) =~ m/::file$/ } @{ $ds->[0]{'Kids'} } ) {
        my ($body_obj) = grep { ref($_) =~ m/::body$/ } @{ $file_obj->{'Kids'} };
        my @groups = grep { ref($_) =~ m/::group$/ } @{ $body_obj->{'Kids'} };

        foreach my $node ( grep { ref($_) =~ m/::trans-unit$/ } @{ $body_obj->{'Kids'} } ) {
            my @source_nodes = grep { ref($_) =~ m/::source$/ } @{ $node->{'Kids'} };
            die "Multiple source tags in one trans-unit!" if @source_nodes > 1;

            my $idx = -1;

          TARGET_NODE:
            for my $target_node ( grep { ref($_) =~ m/::target$/ } @{ $node->{'Kids'} } ) {
                ++$idx;
                die "Multiple target tags in one trans-unit!" if $idx;

                my $source_node = $source_nodes[$idx];
                my $cp_ref_data = undef;

              TARGET_CHILD_NODE:
                for my $child_node ( @{ $target_node->{'Kids'} } ) {
                    if ( exists $child_node->{'cp:ref'} ) {
                        my $cpref = $child_node->{'cp:ref'};
                        $cp_ref_data->{$cpref} = [ grep { $_->{'id'} eq $cpref } @groups ];
                    }
                }

                # if target does not have it, see if source does (e.g. source has quant, target-incorrectly-does not)
                if ( !$cp_ref_data ) {
                    for my $child_node ( @{ $source_node->{'Kids'} } ) {
                        if ( exists $child_node->{'cp:ref'} ) {
                            my $cpref = $child_node->{'cp:ref'};
                            $cp_ref_data->{$cpref} = [ grep { $_->{'id'} eq $cpref } @groups ];
                        }
                    }
                }

                # when a target has things that reference outside structures we use the cp:ref attribute
                # the data it references, as needed by xliff2phrase(), should be in $cp_ref_data
                my $translation = '';
                eval { $translation = $self->xliff2phrase( $target_node, $cp_ref_data ); };

                # (This section can be adjusted later pending error handling appoach.)
                if ($@) {
                    die "ERROR: Encountered fatal error in 'xliff2phrase' for target phrase: $@";
                }

                # Use data from the "cp:lexicon-key" attribute for "arbitrary key" type of bracket notation
                my $arb_key = $source_node->{'cp:lexicon-key'};

                my $source_data;

                # xliff2phrase() will prefer target over source in $cp_ref_data so we need to strip out the target in order to get the right value
                for my $skids ( @{ $source_node->{'Kids'} } ) {
                    if ( ref($skids) && exists $skids->{'cp:ref'} ) {
                        for my $tu ( grep { ref($_) =~ m/::trans-unit$/ } @{ $cp_ref_data->{ $skids->{'cp:ref'} }[0]->{'Kids'} } ) {
                            @{ $tu->{'Kids'} } = grep { ref($_) !~ m/::target$/ } @{ $tu->{'Kids'} };
                        }
                    }
                }

                $source_data = eval { $self->xliff2phrase( $source_nodes[$idx], $cp_ref_data ) };
                if ($@) {
                    die "ERROR: Encountered fatal error in 'xliff2phrase' for source phrase: $@";
                }

                # we have to do this regex to allow for the terrible-but-true (just use locale.numf(0) or use it in a sentence …) case of '0' (while  erroring out on undef, '', '  ', etc)
                if ( $source_data !~ m/\S/ ) {
                    die "ERROR: Unable to obtain data from source element. Unable to continue further...";
                }

                if ($arb_key) {
                    $trans_hr->{$arb_key} = $translation;
                }
                else {
                    $trans_hr->{$source_data} = $translation;
                }
            }
        }
    }

    return $trans_hr;
}

1;
