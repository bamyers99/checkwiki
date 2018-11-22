#! /usr/bin/env perl

###########################################################################
##
##          FILE: dump_dispatcher.pl
##
##         USAGE: ./checkwiki.pl -c checkwiki.cfg
##
##   DESCRIPTION: Checks for new dump files from all languages.
##                If new dump file is found, send checkwiki.pl proccess
##                to the queue.
##
##        AUTHOR: Bryan White
##       LICENCE: GPLv3
##       VERSION: 2015/06/24
##
###########################################################################

use strict;
use warnings;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

binmode( STDOUT, ':encoding(UTF-8)' );

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Projects;
my @Last_Dump;

#Database configuration
my ( $DbName, $DbServer, $DbUsername, $DbPassword, $config_name, $dbh );

GetOptions(
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'config|c=s'   => \$config_name
);

if ( defined $config_name ) {
    open( my $file, '<:encoding(UTF-8)', $config_name )
      or die 'Could not open file ' . $config_name . "\n";
    while ( my $line = <$file> ) {
        chomp($line);
        my @words = ( split / /, $line );
        $DbName     = $words[1] if ( $words[0] =~ /--database/ );
        $DbUsername = $words[1] if ( $words[0] =~ /--user/ );
        $DbPassword = $words[1] if ( $words[0] =~ /--password/ );
        $DbServer   = $words[1] if ( $words[0] =~ /--host/ );
    }
    close($file)
      or die 'Could not close file ' . $config_name . "\n";
}
else {
    die("No config file entered, for example: -c checkwiki.cfg\n");
}

open_db();
get_projects();

my $count        = 0;
my $queued_count = 0;
my $project;

foreach (@Projects) {

    $project = $_;
    # Due to WMFlabs incompetence, below projects are very late showing up
    if (    $project ne 'enwiki'
        and $project ne 'dewiki' )
    {
        my $lastDump = $Last_Dump[$count];
        my ( $latestDumpDate, $latestDumpFilename ) = FindLatestDump();

        print 'PROJECT:'
          . $project
          . '  LASTDUMP'
          . $lastDump
          . '  LATEST:'
          . $latestDumpDate . "\n";
        if ( $queued_count < 10 ) {    # Queue max is 16 jobs at one time.
            if ( !defined($lastDump) || $lastDump ne $latestDumpDate ) {
                queueUp( $latestDumpDate, $latestDumpFilename );
                $queued_count++;
            }
        }
    }
    $count++;

}

close_db();

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            mysql_enable_utf8mb4 => 1,
        }
    ) or die( 'Could not connect to database: ' . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {

    $dbh->disconnect();

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_projects {

    my $sth = $dbh->prepare('SELECT Project, Last_Dump FROM cw_overview;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    my ( $project_sql, $last_dump_sql );
    $sth->bind_col( 1, \$project_sql );
    $sth->bind_col( 2, \$last_dump_sql );

    while ( $sth->fetchrow_arrayref ) {
        push( @Projects,  $project_sql );
        push( @Last_Dump, $last_dump_sql );
    }

    return ();
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub FindLatestDump {

    # the 2 is in the file search to weed out the 'latest' directory which sorts last
    my @Filenames =
      </public/dumps/public/$project/2*/$project-*-pages-articles.xml.bz2>;
    if ( !@Filenames ) {
        return undef;
    }

    if ( $Filenames[-1] !~
m!/public/dumps/public/\Q$project\E/((\d{4})(\d{2})(\d{2}))*/\Q$project\E-\1-pages-articles.xml.bz2!
      )
    {
        die( 'Could not parse filename: ' . $Filenames[-1] . "\n" );
    }

    return ( $2 . q{-} . $3 . q{-} . $4, $Filenames[-1] );
}

###########################################################################
## Send the puppy to the queue
###########################################################################

sub queueUp {
    my ( $date, $file ) = @_;

    system(
        'jsub',
        '-j',         'y',
        '-mem',       '3072m',
        '-N',         $project . '-munch',
        '-o',         '/data/project/checkwiki/var/log',
        '-once',      '/data/project/checkwiki/bin/checkwiki.pl',
        '--config',   '/data/project/checkwiki/checkwiki.cfg',
        '--load',     'dump',
        '--project',  $project,
        '--dumpfile', $file,
        '--tt',
    );

    print "/usr/bin/jsub\n";
    print "-j, y\n";
    print "-mem, 3072m\n";
    print '-N, ' . $project . "-munch\n";
    print "-o, /data/project/checkwiki/var/log\n";
    print "-once /data/project/checkwiki/bin/checkwiki.pl\n";
    print "--config, /data/project/checkwiki/checkwiki.cfg\n";
    print "--load dump\n";
    print '--project,' . $project . "\n";
    print '--dumpfile,' . $file . "\n";
    print "--tt,\n\n\n";

    return();
}