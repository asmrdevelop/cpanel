package Cpanel::Config::LoadConfig;

# cpanel - Cpanel/Config/LoadConfig.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hash::Stringify              ();
use Cpanel::Debug                        ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::LoadFile::ReadFast           ();
use Cpanel::HiRes                        ();
use Cpanel::SV                           ();

use constant _ENOENT => 2;

my $logger;
our $PRODUCT_CONF_DIR = '/var/cpanel';

our $_DEBUG_SAFEFILE = 0;

# We can avoid calculating the md5 of the options if they are common
my %COMMON_CACHE_NAMES = (
    ':__^\s*[#;]____0__'                                                                           => 'default_colon',
    ':\s+__^\s*[#;]____0__'                                                                        => 'default_colon_any_space',
    ': __^\s*[#;]____0__'                                                                          => 'default_colon_with_one_space',
    '=__^\s*[#;]____0__skip_readable_check_____1'                                                  => 'default_skip_readable',
    '=__^\s*[#;]____0__'                                                                           => 'default',
    '=__^\s*[#;]__(?^:\s+)__0__'                                                                   => 'default_with_preproc_newline',
    '=__^\s*[#;]____1__'                                                                           => 'default_allow_undef',
    '\s*[:]\s*__^\s*[#;]____0__'                                                                   => 'default_colon_before_after_space',
    '\s*=\s*__^\s*[#;]____1__'                                                                     => 'default_equal_before_after_space_allow_undef',
    '\s*[\=]\s*__^\s*[#]____0__use_reverse_____0'                                                  => 'default_equal_before_after_space',
    ': __^\s*[#;]____0__limit_____10000000000_____use_reverse_____0'                               => 'default_with_10000000000_limit',
    '\s*[:]\s*__^\s*[#;]____0__use_hash_of_arr_refs_____0_____use_reverse_____0'                   => 'default_use_hash_of_arr_refs',
    ': __^\s*[#;]____0__limit__________use_reverse_____0'                                          => 'default_colon_single_space_no_limit',
    ': __^\s*[#;]____1__skip_keys_____nobody_____use_hash_of_arr_refs_____0_____use_reverse_____0' => 'default_colon_skip_nobody_no_limit',
    ': __^\s*[#;]____1__use_reverse_____1'                                                         => 'default_reverse_allow_undef',
    '\s+__^\s*[#;]____0__'                                                                         => 'default_space_seperated_config',
    '\s*=\s*__^\s*[#;]__^\s*__0__'                                                                 => 'default_equal_space_seperated_config',           #ea4.conf
);

my $DEFAULT_DELIMITER      = '=';
my $DEFAULT_COMMENT_REGEXP = '^\s*[#;]';                                                                                                                #Keep in sync with tr{} below!!
my @BOOLEAN_OPTIONS        = qw(
  allow_undef_values
  use_hash_of_arr_refs
  use_reverse
);

my $CACHE_DIR_PERMS = 0700;

sub _process_parse_args {
    my (%opts) = @_;

    #TODO: Should this check length() instead of defined() ?
    #Leaving it "defined" since that's how it was before the present refactor.
    if ( !defined $opts{'delimiter'} ) {
        $opts{'delimiter'} = $DEFAULT_DELIMITER;
    }

    #Strictly speaking, this "should" allow 0; however, that's not useful
    #and could break some callers that pass in 0 here thinking this was a
    #boolean parameter. (It used to be called "pretreatline".)
    $opts{'regexp_to_preprune'} ||= q{};

    $opts{'comment'} ||= $DEFAULT_COMMENT_REGEXP;

    #If 0E0 is passed in this means we do not want to check
    #for comments however for legacy reasons we always use
    #the $DEFAULT_COMMENT_REGEXP if one is not set so we
    #need a way to tell LoadConfig not to look for comments
    #with the magic 0E0
    $opts{'comment'} = '' if $opts{'comment'} eq '0E0';

    $opts{$_} ||= 0 for @BOOLEAN_OPTIONS;

    return %opts;
}

{
    no warnings 'once';
    *get_homedir_and_cache_dir = *_get_homedir_and_cache_dir;
}

#For testing.
sub _get_homedir_and_cache_dir {
    my ( $homedir, $cache_dir );

    if ( $> == 0 ) {
        $cache_dir = "$PRODUCT_CONF_DIR/configs.cache";
    }
    else {
        {
            no warnings 'once';
            $homedir = $Cpanel::homedir;
        }
        if ( !$homedir ) {
            eval 'local $SIG{__DIE__}; local $SIG{__WARN__}; require Cpanel::PwCache';    ## no critic qw(ProhibitStringyEval) # PPI USE OK - just after
            $homedir = Cpanel::PwCache::gethomedir() if $INC{'Cpanel/PwCache.pm'};
            return unless $homedir;                                                       # undef for homedir and cache_dir avoid issues later when using undef as hash key
        }

        Cpanel::SV::untaint($homedir);

        $homedir =~ tr{/}{}s;

        return ( $homedir, undef ) if $homedir eq '/';
        if ( $ENV{'TEAM_USER'} ) {
            $cache_dir = "$homedir/$ENV{'TEAM_USER'}/.cpanel/caches/config";
        }
        else {
            $cache_dir = "$homedir/.cpanel/caches/config";
        }
    }

    return ( $homedir, $cache_dir );
}

#Parameters:
#   0) The filesystem path
#   1) A reference into which to load the config file's data.
#      - can be undef to create a new hash
#   2) The delimiter between the key and value.
#   3) A regexp for finding an end-of-line comment
#   4) A regexp of stuff to delete from the line before parsing
#   5) Whether to allow undef values (i.e., no delimiter) in the parse.
#   6) A hashref of additional options:
#       delimiter - overrides 2) above
#       comment - overrides 3) above
#       regexp_to_preprune - overrides 4) above
#       allow_undef_values - overrides 5) above
#       limit - max # of entries to read from the source file
#       nocache - forgo caching and force loading the source file
#       skip_readable_check - A small optimization that saves a disk stat()
#       use_reverse - Return keys as values, and vice-versa
#       use_hash_of_arr_refs - Each value will be an array ref, which allows
#           reading >1 value for the same key.
#       empty_is_invalid - An empty cache will be considered an invalid cache
sub loadConfig {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $file, $conf_ref, $delimiter, $comment, $regexp_to_preprune, $allow_undef_values, $arg_ref ) = @_;

    $conf_ref ||= -1;

    my %processed_positional_args = _process_parse_args(
        delimiter          => $delimiter,
        comment            => $comment,
        regexp_to_preprune => $regexp_to_preprune,
        allow_undef_values => $allow_undef_values,
        $arg_ref ? %$arg_ref : (),
    );

    # We don't want the empty_is_invalid parameter to influence the cache name
    # This is only used for reading & to force a reload if the cache is empty
    my $empty_is_invalid = ( defined $arg_ref ) ? delete $arg_ref->{'empty_is_invalid'} : undef;

    my ( $use_reverse, $use_hash_of_arr_refs );
    ( $delimiter, $comment, $regexp_to_preprune, $allow_undef_values, $use_reverse, $use_hash_of_arr_refs ) = @processed_positional_args{
        qw(
          delimiter
          comment
          regexp_to_preprune
          allow_undef_values
          use_reverse
          use_hash_of_arr_refs
        )
    };

    # Cache Hash must be updated if args are added

    if ( !$file || $file =~ tr/\0// ) {
        _do_logger( 'warn', 'loadConfig requires valid filename' );
        if ( $arg_ref->{'keep_locked_open'} ) {
            return ( undef, undef, undef, "loadConfig requires valid filename" );
        }

        return;
    }

    my $filesys_mtime = ( Cpanel::HiRes::stat($file) )[9] or do {
        if ( $arg_ref->{'keep_locked_open'} ) {
            return ( undef, undef, undef, "Unable to stat $file: $!" );
        }
        return;
    };

    # If $conf_ref is -1 we will not waste the overhead of loading it into a hashref
    # as the function calling us just wants the hash(ref) we will return
    my $load_into_conf_ref = ( !ref $conf_ref && $conf_ref == -1 ) ? 0 : 1;

    if ($load_into_conf_ref) {
        $conf_ref = _hashify_ref($conf_ref);
    }

    my ( $homedir, $cache_dir ) = _get_homedir_and_cache_dir();

    my $cache_file;

    Cpanel::AdminBin::Serializer::FailOK::LoadModule() if !$INC{'Cpanel/AdminBin/Serializer.pm'};
    if ( $cache_dir && $INC{'Cpanel/JSON.pm'} && ( !defined $arg_ref || !ref $arg_ref || !exists $arg_ref->{'nocache'} && !$arg_ref->{'keep_locked_open'} ) ) {

        $cache_file = get_cache_file(
            'file'               => $file,
            'cache_dir'          => $cache_dir,
            'delimiter'          => $delimiter,
            'comment'            => $comment,
            'regexp_to_preprune' => $regexp_to_preprune,
            'allow_undef_values' => $allow_undef_values,
            'arg_ref'            => $arg_ref,
        );

        my ( $cache_valid, $ref ) = load_from_cache_if_valid(
            'file'               => $file,
            'cache_file'         => $cache_file,
            'filesys_mtime'      => $filesys_mtime,
            'conf_ref'           => $conf_ref,
            'load_into_conf_ref' => $load_into_conf_ref,
            'empty_is_invalid'   => $empty_is_invalid,
        );

        if ($cache_valid) {
            return $ref;
        }
    }

    # If conf_ref was set to the special value of -1 (we just want a hash(ref) returned)
    # we must create a hashref to store the data we are about to load in
    $conf_ref = {} if !$load_into_conf_ref;

    my $conf_fh;
    my $conflock;
    my $locked;
    if ( $arg_ref->{'keep_locked_open'} || $arg_ref->{'rw'} ) {
        require Cpanel::SafeFile;
        $locked   = 1;
        $conflock = Cpanel::SafeFile::safeopen( $conf_fh, '+<', $file );
    }
    else {
        $conflock = open( $conf_fh, '<', $file );
    }

    if ( !$conflock ) {
        my $open_err = $! || '(unspecified error)';

        local $_DEBUG_SAFEFILE = 1;

        require Cpanel::Logger;
        my $is_root = ( $> == 0 ? 1 : 0 );

        #
        # safeopen does not currently provide the best error so we need
        # to do this here for now.
        #
        if ( !$is_root && !$arg_ref->{'skip_readable_check'} ) {
            if ( !-r $file ) {
                my $msg;

                if ( my $err = $! ) {
                    $msg = "$file’s readability check failed: $err";
                }
                else {
                    my $euser = getpwuid $>;
                    $msg = "$file is not readable as $euser.";
                }

                _do_logger( 'warn', $msg );

                if ( $arg_ref->{'keep_locked_open'} ) {
                    return ( undef, undef, undef, $msg );
                }

                return;
            }
        }
        my $verb = ( $locked ? 'lock/' : q<> ) . 'open';
        my $msg  = "Unable to $verb $file as UIDs $</$>: $open_err";

        Cpanel::Logger::cplog( $msg, 'warn', __PACKAGE__ );
        if ( $arg_ref->{'keep_locked_open'} ) {
            return ( undef, undef, undef, $msg );
        }
        return;
    }

    my ( $parse_ok, $parsed ) = _parse_from_filehandle(
        $conf_fh,
        comment              => $comment,
        delimiter            => $delimiter,
        regexp_to_preprune   => $regexp_to_preprune,
        allow_undef_values   => $allow_undef_values,
        use_reverse          => $use_reverse,
        use_hash_of_arr_refs => $use_hash_of_arr_refs,
        $arg_ref ? %$arg_ref : (),
    );

    if ( $locked && !$arg_ref->{'keep_locked_open'} ) {
        require Cpanel::SafeFile;
        Cpanel::SafeFile::safeclose( $conf_fh, $conflock );
    }

    if ( !$parse_ok ) {
        require Cpanel::Logger;
        Cpanel::Logger::cplog( "Unable to parse $file: $parsed", 'warn', __PACKAGE__ );
        if ( $arg_ref->{'keep_locked_open'} ) {
            return ( undef, undef, undef, "Unable to parse $file: $parsed" );
        }
        return;
    }

    @{$conf_ref}{ keys %$parsed } = values %$parsed;

    if ($cache_file) {
        write_cache(
            'cache_dir'  => $cache_dir,
            'cache_file' => $cache_file,
            'homedir'    => $homedir,
            'is_root'    => ( $> == 0 ? 1 : 0 ),
            'data'       => $parsed,
        );
    }

    if ( $arg_ref->{'keep_locked_open'} ) {
        return $conf_ref, $conf_fh, $conflock, "open success";
    }

    return $conf_ref;
}

sub load_from_cache_if_valid {
    my (%opts) = @_;

    my $cache_file = $opts{'cache_file'} or die "need cache_file!";

    my $file               = $opts{'file'};
    my $conf_ref           = $opts{'conf_ref'};
    my $load_into_conf_ref = $opts{'load_into_conf_ref'};
    my $filesys_mtime      = $opts{'filesys_mtime'} || ( Cpanel::HiRes::stat($file) )[9];

    open( my $cache_fh, '<:stdio', $cache_file ) or do {
        my $err = $!;

        my $msg = "non-fatal error: open($cache_file): $err";

        # Don’t warn if the file just is not there, but do warn
        # if the error is anything else (e.g., permissions).
        warn $msg if $! != _ENOENT();

        return ( 0, $msg );
    };

    my ( $cache_filesys_mtime, $now, $cache_conf_ref ) = ( ( Cpanel::HiRes::fstat($cache_fh) )[9], Cpanel::HiRes::time() );    # stat the file after we have it open to avoid a race condition

    if ( ( $Cpanel::Debug::level || 0 ) >= 5 ) {
        print STDERR __PACKAGE__ . "::loadConfig file:$file, cache_file:$cache_file, cache_filesys_mtime:$cache_filesys_mtime, filesys_mtime:$filesys_mtime, now:$now\n";
    }

    if ( $filesys_mtime && _greater_with_same_precision( $cache_filesys_mtime, $filesys_mtime ) && _greater_with_same_precision( $now, $cache_filesys_mtime ) ) {
        if ( ( $Cpanel::Debug::level || 0 ) >= 5 ) {
            print STDERR __PACKAGE__ . "::loadConfig using cache_file:$cache_file\n";
        }

        Cpanel::AdminBin::Serializer::FailOK::LoadModule() if !$INC{'Cpanel/AdminBin/Serializer.pm'};
        if ( $cache_conf_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile($cache_fh) ) {    #zero keys is a valid file still it may just be all comments or empty
            close($cache_fh);

            if ( $opts{'empty_is_invalid'} && scalar keys %$cache_conf_ref == 0 ) {
                return ( 0, 'Cache is empty' );
            }

            my $ref_to_return;
            if ($load_into_conf_ref) {
                @{$conf_ref}{ keys %$cache_conf_ref } = values %$cache_conf_ref;
                $ref_to_return = $conf_ref;
            }
            else {
                $ref_to_return = $cache_conf_ref;
            }

            return ( 1, $ref_to_return );
        }
        elsif ( ( $Cpanel::Debug::level || 0 ) >= 5 ) {
            print STDERR __PACKAGE__ . "::loadConfig failed to load cache_file:$cache_file\n";
        }

    }
    else {
        if ( ( $Cpanel::Debug::level || 0 ) >= 5 ) {
            print STDERR __PACKAGE__ . "::loadConfig NOT using cache_file:$cache_file\n";
        }
    }

    return ( 0, 'Cache not valid' );
}

sub _greater_with_same_precision {
    my ( $float1, $float2 ) = @_;
    my ( $int1,   $int2 )   = ( int($float1), int($float2) );
    if ( $float1 == $int1 or $float2 == $int2 ) {
        return $int1 > $int2;
    }
    return $float1 > $float2;
}

sub get_cache_file {    ## no critic qw(Subroutines::RequireArgUnpacking) - Args unpacked by _process_parse_args
    my %opts = _process_parse_args(@_);

    die 'need cache_dir!' if !$opts{'cache_dir'};

    # Cache Hash
    my $stringified_args = join(
        '__',
        @opts{qw(delimiter comment regexp_to_preprune allow_undef_values)}, ( scalar keys %{ $opts{'arg_ref'} } ? Cpanel::Hash::Stringify::sorted_hashref_string( $opts{'arg_ref'} ) : '' )
    );
    if ( ( $Cpanel::Debug::level || 0 ) >= 5 ) {    # PPI NO PARSE -  ok missing
        print STDERR __PACKAGE__ . "::loadConfig stringified_args[$stringified_args]\n";
    }

    # Required, since non-destructive substition (/r) isn't available with the Perl that ships with CentOS 6.
    my $safe_filename = $opts{'file'};
    $safe_filename =~ tr{/}{_};

    return $opts{'cache_dir'} . '/' . $safe_filename . '___' . ( $COMMON_CACHE_NAMES{$stringified_args} || _get_fastest_hash($stringified_args) );
}

sub _get_fastest_hash {
    require Cpanel::Hash;
    goto \&Cpanel::Hash::get_fastest_hash;
}

sub write_cache {
    my (%opts)     = @_;
    my $cache_file = $opts{'cache_file'};
    my $cache_dir  = $opts{'cache_dir'};
    my $homedir    = $opts{'homedir'};
    my $is_root    = $opts{'is_root'};
    my $parsed     = $opts{'data'};

    my @dirs = ($cache_dir);
    if ( !$is_root ) {
        if ( $ENV{'TEAM_USER'} ) {
            unshift @dirs, "$homedir/$ENV{'TEAM_USER'}", "$homedir/$ENV{'TEAM_USER'}/.cpanel", "$homedir/$ENV{'TEAM_USER'}/.cpanel/caches";
        }
        else {
            unshift @dirs, "$homedir/.cpanel", "$homedir/.cpanel/caches";
        }
    }

    foreach my $dir (@dirs) {
        Cpanel::SV::untaint($dir);

        # We always chmod here because we did not
        # always set the permissions in very old
        # version of cPanel.
        chmod( $CACHE_DIR_PERMS, $dir ) or do {
            if ( $! == _ENOENT() ) {

                # Ensure that we create with the right permissions.
                require Cpanel::Umask;
                my $umask = Cpanel::Umask->new(0);

                mkdir( $dir, $CACHE_DIR_PERMS ) or do {
                    _do_logger( 'warn', "Failed to create dir “$dir”: $!" );
                };
            }
            else {
                _do_logger( 'warn', "chmod($dir): $!" );
            }
        };

    }

    #Since the directory is already 0700 the perms on this file
    #shouldn’t matter, but a bit of extra paranoia never hurts...
    my $wrote_ok = eval { Cpanel::FileUtils::Write::JSON::Lazy::write_file( $cache_file, $parsed, 0600 ) };
    my $error    = $@;

    # Don't warn if we didn't write it because this is a fresh install and
    # JSON::XS isn't available ($wrote_ok is 0).
    $error ||= "Unknown error" if !defined $wrote_ok;
    if ($error) {
        _do_logger( 'warn', "Could not create cache file “$cache_file”: $error" );
        unlink $cache_file;    #outdated
    }
    if ( ( $Cpanel::Debug::level || 0 ) > 4 ) {    # PPI NO PARSE -  ok missing
        print STDERR __PACKAGE__ . "::loadConfig [lazy write cache file] [$cache_file] wrote_ok:[$wrote_ok]\n";
    }
    return 1;
}

sub _do_logger {
    my ( $action, $msg ) = @_;

    require Cpanel::Logger;
    $logger ||= Cpanel::Logger->new();

    return $logger->$action($msg);
}

#opts are as follows. See above for definitions:
#   comment
#   limit
#   regexp_to_preprune
#   delimiter
#   allow_undef_values
#   use_hash_of_arr_refs
#   skip_keys
#   use_reverse
sub parse_from_filehandle {
    my ( $conf_fh, %opts ) = @_;
    return _parse_from_filehandle( $conf_fh, _process_parse_args(%opts) );
}

sub _parse_from_filehandle {
    my ( $conf_fh, %opts ) = @_;

    # All callers already _process_parse_args
    # It should not be done here as its
    # destructive

    my ( $comment, $limit, $regexp_to_preprune, $delimiter, $allow_undef_values, $use_hash_of_arr_refs, $skip_keys, $use_reverse ) = @opts{
        qw(
          comment
          limit
          regexp_to_preprune
          delimiter
          allow_undef_values
          use_hash_of_arr_refs
          skip_keys
          use_reverse
        )
    };

    my $conf_ref = {};

    #
    # Decide which parser to use
    # Simple slurp file into hash split on delimiter (about 3 times faster then a parsed load)
    #   OR
    # Parsed faile load
    #
    my $parser_code;
    my ( $k, $v );    ## no critic qw(Variables::ProhibitUnusedVariables)
    my $keys           = 0;
    my $key_value_text = $use_reverse ? '1,0' : '0,1';
    my $cfg_txt        = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $conf_fh, $cfg_txt );
    my $has_cr = index( $cfg_txt, "\r" ) > -1 ? 1 : 0;
    _remove_comments_from_text( \$cfg_txt, $comment, \$has_cr ) if $cfg_txt && $comment;

    my $split_on = $has_cr ? '\r?\n' : '\n';

    if ( !$limit && !$regexp_to_preprune && !$use_hash_of_arr_refs && length $delimiter ) {
        ##
        ##
        ## If we are just loading the file up into a hash (regular or reverse)
        ## we can do it with a single map statement to make this about 65% faster
        ## we do it in an eval so we can insert the regex in the code and avoid /o
        ## empty lines end up in one hash key which we remove with the delete
        ##
        if ($allow_undef_values) {
            $parser_code = qq<
                  \$conf_ref = {
                      map {
                          (split(m/> . $delimiter . qq</, \$_, 2))[$key_value_text]
                      } split(/> . $split_on . qq</, \$cfg_txt)
                  };
              >;
        }
        else {
            $parser_code = ' $conf_ref = {  map { ' . '($k,$v) = (split(m/' . $delimiter . '/, $_, 2))[' . $key_value_text . ']; ' . 'defined($v) ? ($k,$v) : () ' . '} split(/' . $split_on . '/, $cfg_txt ) }';
        }
    }
    else {
        if ( ( $Cpanel::Debug::level || 0 ) > 4 ) {    # PPI NO PARSE - ok if not there
            $limit ||= 0;
            print STDERR __PACKAGE__ . "::parse_from_filehandle [slow LoadConfig parser used] LIMIT:[!$limit] REGEXP_TO_DELETE[!$regexp_to_preprune] USE_HASH_OF_ARR_REFS[$use_hash_of_arr_refs)]\n";
        }
        ##
        ## Here we build the parser code
        ## This is a much much faster way of doing things than iterating "normally"
        ## Since the options are only checked once, not on each loop
        ##
        $parser_code = 'foreach (split(m/' . $split_on . '/, $cfg_txt)) {' . "\n"                                                                            #
          . q{next if !length;} . "\n"                                                                                                                       #
          . ( $limit ? q{last if $keys++ == } . $limit . ';' : '' ) . "\n" . ( $regexp_to_preprune ? q{ s/} . $regexp_to_preprune . q{//g;} : '' ) . "\n"    #
          . (
            length $delimiter ?                                                                                                                              #
              (
                q{( $k, $v ) = (split( /} . $delimiter . q{/, $_, 2 ))[} . $key_value_text . q{];} . "\n" .                                                  #
                  ( !$allow_undef_values  ? q{ next if !defined($v); }          : '' ) . "\n" .                                                              #
                  ( $use_hash_of_arr_refs ? q{ push @{ $conf_ref->{$k} }, $v; } : q{ $conf_ref->{$k} = $v; } ) . "\n"                                        #
              )
            : q{$conf_ref->{$_} = 1; } . "\n"
          ) . '};';
    }

    $parser_code .= "; 1";
    $parser_code =~ tr{\n}{\r};    ## no critic qw(Cpanel::TransliterationUsage)
                                   #
                                   # This should probably NEVER fail, but if it does we want to panic
                                   #
    eval($parser_code) or do {     ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        $parser_code =~ tr{\r}{\n};    ## no critic qw(Cpanel::TransliterationUsage)
        _do_logger( 'panic', "Failed to parse :: $parser_code: $@" );
        return ( 0, "$@\n$parser_code" );
    };

    #this can only happen if there was an empty line
    delete $conf_ref->{''} if !defined( $conf_ref->{''} );

    # option to skip certain keys -- we do post processing as we almost always
    # want to keep more key than we remove so its much faster
    if ($skip_keys) {
        my $skip_keys_ar;
        if ( ref $skip_keys eq 'ARRAY' ) {
            $skip_keys_ar = $skip_keys;
        }
        elsif ( ref $skip_keys eq 'HASH' ) {
            $skip_keys_ar = [ keys %$skip_keys ];
        }
        else {
            return ( 0, 'skip_keys must be an ARRAY or HASH reference' );
        }
        delete @{$conf_ref}{@$skip_keys_ar};
    }

    return ( 1, $conf_ref );
}

sub _hashify_ref {
    my $conf_ref = shift;

    if ( !defined($conf_ref) ) {
        $conf_ref = {};
        return $conf_ref;
    }

    unless ( ref $conf_ref eq 'HASH' ) {
        if ( ref $conf_ref ) {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( 'hashifying non-HASH reference', 'warn', __PACKAGE__ );

            # This code does not work against CODE, ARRAY, and possibly
            # blessed and LVALUE references.
            # It works against SCALAR, HASH, REF, GLOB references.only...
            ${$conf_ref} = {};
            $conf_ref = ${$conf_ref};
        }
        else {
            require Cpanel::Logger;
            Cpanel::Logger::cplog( 'defined value encountered where reference expected', 'die', __PACKAGE__ );
        }
    }
    return $conf_ref;
}

sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

sub _remove_comments_from_text {
    my ( $cfg_txt_sr, $comment, $has_cr_sr ) = @_;
    if ($$has_cr_sr) {
        $$cfg_txt_sr = join( "\n", grep ( !m/$comment/, split( m{\r?\n}, $$cfg_txt_sr ) ) );
        $$has_cr_sr  = 0;
    }
    elsif ( $comment eq $DEFAULT_COMMENT_REGEXP ) {

        # Try a cheap strip if the header first
        if ( rindex( $$cfg_txt_sr, '#', 0 ) == 0 && index( $$cfg_txt_sr, "\n" ) > -1 ) {
            substr( $$cfg_txt_sr, 0, index( $$cfg_txt_sr, "\n" ) + 1, '' );
        }
        $$cfg_txt_sr =~ s{$DEFAULT_COMMENT_REGEXP.*}{}omg if $$cfg_txt_sr =~ tr{#;}{};
    }
    else {
        $$cfg_txt_sr =~ s{$comment.*}{}mg;
    }
    return 1;
}

1;
