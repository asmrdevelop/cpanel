package Cpanel::MysqlUtils::MyCnf::Modify;

# cpanel - Cpanel/MysqlUtils/MyCnf/Modify.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles             ();
use Cpanel::MysqlUtils::MyCnf::Full ();
use Cpanel::MysqlUtils::MyCnf       ();
use Cpanel::FileUtils::Write        ();

#$code will receive as arguments:
#   - the section name
#   - the key of a particular setting
#   - the value of that setting
#
#...and is expected to return one of:
#   - { newkey => newvalue }    ...to replace the line
#   - [ 'COMMENT' ]             ...to comment the current line out
#   - (anything else)           ...to leave the line as-is
#
#TODO: Report errors somehow.
#
sub modify {
    my ( $code, $mycnffile ) = @_;

    $mycnffile ||= $Cpanel::ConfigFiles::MYSQL_CNF;

    my $perms = 0600;
    if ( -e $mycnffile ) {
        $perms = ( stat($mycnffile) )[2] & 0777;
    }

    # Parse the my.cnf file while preserving the comments and line order
    my $mycnf = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf_preserve_lines($mycnffile);
    return unless $mycnf;

    # Go through each line of the file, modifying if need be,
    # and append to the our data string so we can write it back to the file
    my $data = '';
    foreach my $line_item (@$mycnf) {

        # If it doesn't have a section or key, nothing to transform, keep as is
        # All lines outside of a section, or ones that are strictly a comment will
        # preserved as-is
        if ( !$line_item->{'section'} or !$line_item->{'key'} ) {
            $data .= $line_item->{'line'};
            next;
        }

        # Try a transform & see what we get
        my $xform = $code->( $line_item->{'section'}, $line_item->{'key'}, $line_item->{'value'} );

        # If it got turned into a comment, comment it out
        # When the transform code wants to remove a line,
        # it returns an array with 'COMMENT' as the first value
        if ( ref $xform eq 'ARRAY' and $xform->[0] eq 'COMMENT' ) {
            $data .= '# ' . $line_item->{'line'};
        }
        elsif ( ref $xform eq 'HASH' ) {

            # Here the transform code changed the key and/or value
            # We know this because it returned a hash which will contain the key value pair
            # Create a new replacement my.cnf file line with the new key/value
            for my $key ( keys %$xform ) {
                my $value = $xform->{$key};

                my $new_line = Cpanel::MysqlUtils::MyCnf::_get_my_cnf_line_for( $key, $value, $line_item->{'line'} );

                if ( !Cpanel::MysqlUtils::MyCnf::_does_line_key_match( $line_item->{'line'}, $key ) ) {

                    # put back the eol comment if need be
                    if ( $line_item->{'eol_comment'} ) {
                        chomp $new_line;
                        $new_line .= $line_item->{'eol_comment'} . "\n";
                    }
                }

                $data .= $new_line;
            }
        }
        else {
            # No transform happened
            # Pass this line along as-is
            $data .= $line_item->{'line'};
        }
    }

    Cpanel::FileUtils::Write::overwrite_no_exceptions( $mycnffile, $data, $perms, 0 );

    return;
}

# add parameters to my.cnf file if they do not already exist
# IN $mycnffile - path to my.cnf
# IN @items_to_add - array of refs in the format the same as
#       Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf_preserve_lines.

sub add {
    my ( $mycnffile, @items_to_add ) = @_;

    if ( !-e $mycnffile ) {
        return;
    }

    my $perms = 0600;
    if ( -e $mycnffile ) {
        $perms = ( stat($mycnffile) )[2] & 0777;
    }

    if ( @items_to_add > 0 ) {

        # special cases are added to the file, actually prepended to the
        # beginning of the target section

        my $mycnf_parsed = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf($mycnffile);
        my $mycnf        = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf_preserve_lines($mycnffile);

        # The section of the key may not already exist and we still want to
        # add it so the best way is to find the needed sections and add them
        # at the end of the $mycnf if they do not exist in $mycnf_parsed.

        my %needed_sections;

        foreach my $ref (@items_to_add) {
            $needed_sections{ $ref->{'section'} } = 1;
        }

        foreach my $section ( keys %needed_sections ) {
            if ( !exists $mycnf_parsed->{$section} ) {
                my $section_ref = {
                    'value'   => undef,
                    'section' => $section,
                    'key'     => undef,
                    'line'    => "[$section]\n",
                };

                push( @$mycnf, $section_ref );
            }
        }

        my $bModified = 0;

        foreach my $ref (@items_to_add) {
            my @output;

            my $key_wdashes      = $ref->{'key'};
            my $key_wunderscores = $ref->{'key'};

            $key_wdashes      =~ tr:_:-:;
            $key_wunderscores =~ tr:-:_:;

            # verify that the key does not already exist in the section, if so
            # skip

            if ( exists $ref->{'section'} && exists $mycnf_parsed->{ $ref->{'section'} }->{$key_wdashes} ) {
                next;
            }

            if ( exists $ref->{'section'} && exists $mycnf_parsed->{ $ref->{'section'} }->{$key_wunderscores} ) {
                next;
            }

            foreach my $mref (@$mycnf) {
                push( @output, $mref );

                # defined is used on purpose for $mref->{'key'}, if key is
                # undef this is the section header

                if ( exists $mref->{'section'} && $mref->{'section'} eq $ref->{'section'} && !defined $mref->{'key'} ) {
                    $bModified = 1;
                    push( @output, $ref );
                }
            }

            $mycnf = \@output;
        }

        if ( $bModified == 0 ) {
            return;
        }

        my $data = '';
        foreach my $mref (@$mycnf) {
            $data .= $mref->{'line'};
        }

        Cpanel::FileUtils::Write::overwrite_no_exceptions( $mycnffile, $data, $perms, 0 );
    }

    return;
}

1;
