<?php
/**
 Copyright 2026 Myers Enterprises II

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 https://enterprise.wikimedia.com/docs/snapshot/
 https://enterprise.wikimedia.com/docs/data-dictionary/
 
 toolforge jobs run enterprisehtml --image php8.4 --command "php bin/enterprise_html.php nlwiki"
 
 */

DEFINE('SUPPLEMENT_TYPE_HASREF', 1);
DEFINE('SUPPLEMENT_SOURCE', 1);

if ($argc < 2) {
    echo 'Usage: enterprise_html.php "project_name or monthly"';
    exit;
}

$daily_projects = ['enwiki', 'dewiki', 'eswiki', 'frwiki', 'arwiki', 'cswiki', 'plwiki', 'bnwiki', 'nlwiki', 'nowiki', 'cawiki', 'hewiki',
    'ruwiki', 'itwiki', 'ptwiki', 'ukwiki'];

$monthly_projects = ['alswiki', 'barwiki', 'dawiki', 'elwiki' ,'nds_nlwiki' ,'scowiki'];

$project_name = $argv[1];

if ($project_name == 'monthly') $project_list = $monthly_projects;
else $project_list = [$project_name];

$hndl = fopen('/data/project/checkwiki/checkwiki.cfg', 'r');
$config = [];
$chunked = false;

while (! feof($hndl)) {
    $buffer = rtrim(fgets($hndl));
    if (empty($buffer)) continue;
    
    $parts = explode(' ', $buffer, 2);
    $key = substr($parts[0], 2); // skip --
    $value = $parts[1];
    
    $config[$key] = $value;
}

fclose($hndl);

$dbh_wikidata = new PDO("mysql:host={$config['host']};dbname={$config['database']};charset=utf8mb4", $config['user'], $config['password']);
$dbh_wikidata->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

foreach ($project_list as $project_name) {
    process_project($project_name);
}

/**
 * Process a project
 * 
 * @param string $project_name
 */
function process_project($project_name)
{
    global $dbh_wikidata, $chunked;
    
    // Lookup project id
    $sql = 'SELECT ID FROM cw_overview WHERE Project = ?';
    $sth = $dbh_wikidata->prepare($sql);
    $sth->execute([$project_name]);
    $results = $sth->fetchAll(PDO::FETCH_NUM);
    
    if (count($results) != 1) {
        echo "Project not found = $project_name\n";
        return;
    }
    
    $project_num = $results[0][0];
    
    $sql = "DELETE FROM cw_supplement WHERE ProjectNo = $project_num AND Source = " . SUPPLEMENT_SOURCE;
    $dbh_wikidata->exec($sql);
    
    if ($chunked) {
        // Retrieve the chunk list
        $url = "https://api.enterprise.wikimedia.com/v2/snapshots/{$project_name}_namespace_0/chunks";
        
        $chunk_list = retrieve_url($url, 'string');
        $chunk_list = json_decode($chunk_list, true);
        
        foreach ($chunk_list as $chunk) {
            $chunk_id = $chunk['identifier'];
            $url = "https://api.enterprise.wikimedia.com/v2/snapshots/{$project_name}_namespace_0/chunks/$chunk_id/download";
            $outfile = 'enterprise_html_chunk.tar.gz';
            
            retrieve_url($url, 'file', $outfile);
            
            process_chunk($project_num, $outfile);
            
            unlink($outfile);
            /* remove */
            break;
        }
    } else {
        // Use beta complete file
        $url = "https://api.enterprise.wikimedia.com/v2/snapshots/structured-contents/{$project_name}_namespace_0/download";
        $outfile = 'enterprise_html.tar.gz';
        
        retrieve_url($url, 'file', $outfile);
        
        process_chunk($project_num, $outfile);
        
        unlink($outfile);
    }
    
}

/**
 * Process a chunk
 * 
 * @param int $project_num
 * @param string $infile
 */
function process_chunk($project_num, $infile)
{
    global $dbh_wikidata;
    
    $sql = "INSERT IGNORE INTO cw_supplement VALUES ($project_num,?," . SUPPLEMENT_TYPE_HASREF . ',' . SUPPLEMENT_SOURCE . ",'')";
    $sth = $dbh_wikidata->prepare($sql);
    
    $handle = gzopen($infile, 'rb');
    
    while (!gzeof($handle)) {
        $buffer = gzgets($handle);
        $page = json_decode($buffer, true);
        
        $references = isset($page['references']) ? $page['references'] : false;
        
        if ($references === false) continue;
        
        $sth->execute([$page['name']]);
        
        //if ($page['name'] == 'Scheme') print_r($page);
        
        //if ($page['name'] == 'Scheme') break;
    }
    
    gzclose($handle);
}

/**
 * Retrieve a url
 * 
 * @param string $url
 * @param string $fetch_type file or string
 * @param string $output_file_path required for type file
 */
function retrieve_url($url, $fetch_type, $output_file_path = '')
{
    $ch = curl_init();
    
    if ($fetch_type == 'file') $fp = fopen($output_file_path, 'w');
    
    curl_setopt($ch, CURLOPT_HEADER, 0);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Checkwiki (checkwiki.support@tools.wmflabs.org)');
    curl_setopt($ch, CURLOPT_URL, $url);
    
    if ($fetch_type == 'file') curl_setopt($ch, CURLOPT_FILE, $fp);
    else curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    
    $page = curl_exec($ch);
    
    if ($fetch_type == 'file') fclose($fp);
    
    return $page;
}
