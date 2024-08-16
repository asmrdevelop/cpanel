package Cpanel::Config::LoadConfig::Tiny;

# cpanel - Cpanel/Config/LoadConfig/Tiny.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#
# *** WARNING ***  this tiny version of Cpanel::Config::LoadConfig does not use safefile locking
# thats perfectly reasonable if all the config files it is reading are rename()d into place
#

##TODO: Refactor this to use parse_from_filehandle() in the main LoadConfig module.

our $_ENOENT = 2;

sub loadConfig {    ## no critic qw(RequireArgUnpacking ProhibitExcessComplexity)
    my ( $file, $conf_ref, $delimiter, $comment, $pretreatline, $allow_undef_values, $arg_ref ) = (
        $_[0],
        $_[1] || -1,
        ( defined $_[2] ? $_[2] : '=' ),
        ( $_[3] || '^\s*[#;]' ),
        ( $_[4] || 0 ),
        ( $_[5] || 0 ),
        $_[6]
    );

    # Cache Hash must be updated if args are added

    # more options
    my $use_reverse          = 0;
    my $use_hash_of_arr_refs = 0;

    die('loadConfig requires valid filename') if !$file || $file =~ tr/\0//;

    # option to use value as key, and name as value.
    if ( defined($arg_ref) && exists( $arg_ref->{'use_reverse'} ) ) {
        $use_reverse = $arg_ref->{'use_reverse'};
    }
    if ( $use_reverse == 0 ) {
        delete $arg_ref->{'use_reverse'};    # should not have been sent -- delete to prevent dupe caching
    }

    # option to use hash of array references.
    if ( exists( $arg_ref->{'use_hash_of_arr_refs'} ) && defined( $arg_ref->{'use_hash_of_arr_refs'} ) ) {
        $use_hash_of_arr_refs = $arg_ref->{'use_hash_of_arr_refs'};
    }
    if ( $use_hash_of_arr_refs == 0 ) {
        delete $arg_ref->{'use_hash_of_arr_refs'};    #should not have been sent -- delete to prevent dupe caching
    }
    my $limit = exists $arg_ref->{'limit'} ? int( $arg_ref->{'limit'} || 0 ) : 0;

    $conf_ref = {} if !ref $conf_ref;
    my $key_value_text = $use_reverse ? '1,0' : '0,1';

    my $fh;

    if ( open( $fh, '<', $file ) ) {
        local $/;

        my $parser_code;

        if ( $use_hash_of_arr_refs || $pretreatline || $allow_undef_values || !length $delimiter ) {
            $parser_code = '
            my ($keys, $name, $value);
LINELOOP:
            foreach my $line (split(/\r?\n/, readline($fh) )) {' . "\n"
              . q{next LINELOOP if $line eq '';} . "\n"
              . ( $comment              ? q{next LINELOOP if ( $line =~ m/$comment/o );}                                                                                       : '' ) . "\n"
              . ( $limit                ? q{last if $keys++ == } . $limit . ';'                                                                                                : '' ) . "\n"
              . ( $pretreatline         ? q{$line =~ s/$pretreatline//go;}                                                                                                     : '' ) . "\n"
              . ( length $delimiter     ? ( $use_reverse ? q{( $value, $name ) = split( /$delimiter/, $line, 2 );} : q{( $name, $value ) = split( /$delimiter/, $line, 2 );} ) : q{($name,$value) = ($line,1);} ) . "\n"
              . ( !$allow_undef_values  ? q{ next LINELOOP if !defined($value); }                                                                                              : '' ) . "\n"
              . ( $use_hash_of_arr_refs ? q{ push @{ $conf_ref->{$name} }, $value; }                                                                                           : q{ $conf_ref->{$name} = $value; } ) . '
           }';
        }
        elsif ($comment) {
            $parser_code = 'my ($k, $v, $count); %{$conf_ref}=(  %$conf_ref, map { ' . 'if (m{' . $comment . '}) { (); } else { ' . '($k,$v) = (split(m/' . $delimiter . '/, $_, 2))[' . $key_value_text . ']; ' . ( $limit ? ' $count++ < $limit && ' : '' ) . 'defined($v) ? ($k,$v) : (); ' . '} } split(/\r?\n/, readline($fh) ) )';
        }
        else {
            $parser_code = 'my ($k, $v); %{$conf_ref}=(  %$conf_ref, map { ' . '($k,$v) = (split(m/' . $delimiter . '/, $_, 2))[' . $key_value_text . ']; ' . ( $limit ? ' $count++ < $limit && ' : '' ) . 'defined($v) ? ($k,$v) : () ' . '} split(/\r?\n/, readline($fh) ) )';
        }

        eval $parser_code;    ## no critic qw(StringyEval)

        if ($@) {
            die "Failed to parse $file: $@";
        }
    }
    elsif ( $! != $_ENOENT ) {
        warn "open(<$file): $!";
    }

    return wantarray ? %{$conf_ref} : $conf_ref;
}
1;
