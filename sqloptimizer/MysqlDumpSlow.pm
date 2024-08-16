package MysqlDumpSlow;

# This module is subject to GPL v2

# mysqldumpslow - parse and summarize the MySQL slow query log

# Original version by Tim Bunce, sometime in 2000.
# Further changes by Tim Bunce, 8th March 2001.
# Handling of strings with \ and double '' by Monty 11 Aug 2001.
# Modified by cPanel, Inc 2008

sub fetch_slow_queries {
    my $file = shift;
    my $opt  = shift || {};
    open( my $fh, '<', $file );
    if ( !$fh ) { return; }
    my $db;
    my %stmt;
    my @pending;
    $/ = ";\n#";    # read entire statements using paragraph mode

    while ( defined( $_ = shift @pending ) or defined( $_ = readline($fh) ) ) {
        warn "[[$_]]\n" if $opt->{'d'};    # show raw paragraph being read

        #        warn "[[$_]]\n";

        my @chunks = split /^\/.*Version.*started with[\000-\377]*?Time.*Id.*Command.*Argument.*\n/m;
        if ( @chunks > 1 ) {
            unshift @pending, map { length($_) ? $_ : () } @chunks;
            warn "<<" . join( ">>\n<<", @chunks ) . ">>" if $opt->{'d'};
            next;
        }

        s/^#? Time: \d{6}\s+\d+:\d+:\d+.*\n//;
        my ( $user, $host ) =
          s/^#? User\@Host:\s+(\S+)\s+\@\s+(\S+).*\n//
          ? ( $1, $2 )
          : ( '', '' );

        s/^# Query_time: (\d+)  Lock_time: (\d+)  Rows_sent: (\d+).*\n//;
        my ( $t, $l, $r ) = ( $1, $2, $3 );
        $t -= $l unless $opt->{'l'};

        # remove fluff that mysqld writes to log when it (re)starts:
        s!^/.*Version.*started with:.*\n!!mg;
        s!^Tcp port: \d+  Unix socket: \S+\n!!mg;
        s!^Time.*Id.*Command.*Argument.*\n!!mg;

        if (/^\s*use\s+(\w+);/) {

            # not consistently added
            $db = $1;
        }
        s/^use \w+;\n//;
        s/^SET timestamp=\d+;\n//;

        s/^[ 	]*\n//mg;         # delete blank lines
        s/^[ 	]*/  /mg;         # normalize leading whitespace
        s/\s*;\s*(#\s*)?$//;    # remove trailing semicolon(+newline-hash)

        s/\b\d+\b/000/g;
        s/\b0x[0-9A-Fa-f]+\b/000/g;
        s/''/'S'/g;
        s/""/"S"/g;
        s/(\\')//g;
        s/(\\")//g;
        s/'[^']+'/'S'/g;
        s/"[^"]+"/"S"/g;

        # abbreviate massive "in (...)" statements and similar
        s!(([NS],){100,})!sprintf("$2,{repeated %d times}",length($1)/2)!eg;

        my $s = $stmt{$_} ||= { users => {}, hosts => {} };
        $s->{c} += 1;
        $s->{t} += $t;
        $s->{d} = $db;
        $s->{l} += $l;
        $s->{r} += $r;

        #       $s->{users}->{$user}++ if $user;
        #        $s->{hosts}->{$host}++ if $host;

        warn "{{$_}}\n\n" if $opt->{'d'};    # show processed statement string
    }
    close($fh);

    return \%stmt;
}

1;
