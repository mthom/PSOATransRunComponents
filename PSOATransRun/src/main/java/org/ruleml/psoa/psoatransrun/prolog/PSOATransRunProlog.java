package org.ruleml.psoa.psoatransrun.prolog;

import gnu.getopt.Getopt;
import gnu.getopt.LongOpt;

import java.io.*;
import java.nio.file.Files;
import java.util.Map.Entry;
import java.util.*;

import org.apache.commons.exec.OS;
import org.ruleml.psoa.psoa2x.common.TranslatorException;
import org.ruleml.psoa.psoa2x.psoa2prolog.PSOA2PrologConfig;
import org.ruleml.psoa.psoa2x.psoa2prolog.PrologTranslator;
import org.ruleml.psoa.psoatransrun.PSOATransRun;

import com.declarativa.interprolog.*;

import static org.ruleml.psoa.psoatransrun.utils.IOUtil.*;

public class PSOATransRunProlog
{
	private static PrologEngine _engine;
	private static boolean _outputTrans = false, _getAllAnswers = false, _showOrigKB = false;
	private static PSOA2PrologConfig _config = new PSOA2PrologConfig();
//	private static int _maxDepth = 0;

	public static void main(String[] args) throws TranslatorException, IOException
	{
		LongOpt[] opts = new LongOpt[]
		{
			new LongOpt("help", LongOpt.NO_ARGUMENT, null, '?'),
			new LongOpt("input", LongOpt.REQUIRED_ARGUMENT, null,'i'),
			new LongOpt("printTrans", LongOpt.NO_ARGUMENT, null,'p'),
			new LongOpt("outputTrans", LongOpt.REQUIRED_ARGUMENT, null,'o'),
			new LongOpt("xsbfolder", LongOpt.REQUIRED_ARGUMENT, null,'x'),
			new LongOpt("query", LongOpt.REQUIRED_ARGUMENT, null, 'q'),
			new LongOpt("allAns", LongOpt.NO_ARGUMENT, null, 'a'),
//			new LongOpt("termDep", LongOpt.REQUIRED_ARGUMENT, null, 'd'),
//			new LongOpt("timeout", LongOpt.REQUIRED_ARGUMENT, null,'t'),
			new LongOpt("repClass", LongOpt.NO_ARGUMENT, null, 'r'),
			new LongOpt("staticOnly", LongOpt.NO_ARGUMENT, null, 's'),
			new LongOpt("echoInput", LongOpt.NO_ARGUMENT, null, 'e')
		};

		Getopt optionsParser = new Getopt("", args, "?i:po:x:q:ad:t:rse", opts);
		File kbFile = null;
		FileInputStream kbStream = null,
						queryStream = null;
//		boolean outputTrans = false;
		String xsbFolder = null;
		File transKBFile = null;
		String arg;
		
		for (int opt = optionsParser.getopt(); opt != -1; opt = optionsParser.getopt())
		{
			switch (opt) {
				case '?':
					printUsage();
					return;
	
				case 'i':
					arg = optionsParser.getOptarg(); 
					try
					{
						kbFile = new File(arg);
						kbStream = new FileInputStream(kbFile);
					}
					catch (FileNotFoundException e)
					{
						printErrln("Cannot find KB file ", arg);
						System.exit(1);
					}
					catch (SecurityException e)
					{
						printErrln("Unable to read KB file ", arg);
						System.exit(1);
					}
					break;
				
//				case 'd':
//					arg = optionsParser.getOptarg();
//					_maxDepth = Integer.parseInt(arg);
//					break;
				case 'q':
					arg = optionsParser.getOptarg(); 
					try
					{
						queryStream = new FileInputStream(arg);
					}
					catch (FileNotFoundException e)
					{
						printErrln("Cannot find query file ", arg, ". Read from console.");
					}
					catch (SecurityException e)
					{
						printErrln("Unable to read query file ", arg, ". Read from console.");
					}
					break;
				case 'r':
					_config.reproduceClass = true;
					break;
				case 'p':
					_outputTrans = true;
					break;
				case 'o':
					arg = optionsParser.getOptarg();
					if (!arg.endsWith(".pl") && !arg.endsWith(".P"))
						printErrlnAndExit("Illegal translation output file name must end with .pl or .P: ", arg);
					transKBFile = new File(arg);
					break;
				case 'x':
					xsbFolder = optionsParser.getOptarg();
					break;
				case 'a':
					_getAllAnswers = true;
					break;
				case 's':
					_config.dynamicObj = false;
					break;
				case 'e':
					_showOrigKB = true;
				default:
					assert false;
			}
		}

		if (kbStream == null)
			printErrlnAndExit("Input KB must be specified.");
		
		if (xsbFolder == null)
			xsbFolder = System.getenv("XSB_DIR");
		
		if (xsbFolder == null)
			printErrlnAndExit("Unable to locate XSB installation folder.");
		
		File f = new File(xsbFolder);
		if (!(f.exists() && f.isDirectory()))
			printErrlnAndExit("XSB installation folder ", xsbFolder, " does not exist");
		
		if (OS.isFamilyUnix() || OS.isFamilyMac())
		{
			f = new File(f, "config");
			File[] subdirs = f.listFiles();
			if (subdirs == null || subdirs.length == 0)
				printErrlnAndExit("Cannot find XSB binary: ", f.getAbsolutePath(), " does not exist or is empty.");
			
			File xsbFile = null;
			for (File dir : subdirs)
			{
				File f1 = new File(dir, "bin/xsb");
				if (f1.canExecute())
					xsbFile = f1;
				
				if (dir.getName().contains("86"))
//				if (dir.getName().contains("btc"))
					break;
			}
			
			if (xsbFile != null)
				_engine = new XSBSubprocessEngine(xsbFile.getAbsolutePath());
			else
				printErrlnAndExit("Cannot find executable xsb binary in ", f.getAbsolutePath());
		}
		else if (OS.isFamilyWindows())
		{
			f = new File(f, "config\\x86-pc-windows\\bin\\xsb");
			_engine = new XSBSubprocessEngine(f.getAbsolutePath());
		}
		else
		{
			printErrlnAndExit("Unsupported operating system.");
		}
		
		PrologTranslator translator = new PrologTranslator(_config);
		String transKB = translator.translateKB(kbStream);
//		System.out.println("Translation finished.");
		
		if (transKBFile == null)
			transKBFile = tmpFile("tmp-", ".pl");
		PrintWriter writer = new PrintWriter(transKBFile);
		writer.println(":- table(memterm/2).");
		if (_config.reproduceClass)
			writer.println(":- table(sloterm/4).");
		else
			writer.println(":- table(sloterm/3).");
		
		for (int i = 2; i < 11; i++)
		{
			writer.println(":- table(tupterm/" + i + ").");
		}
		
		writer.println(":- set_prolog_flag(unknown,fail).");
		writer.print(transKB);
		writer.close();

		if (_showOrigKB)
		{
			println("Original KB:");
			BufferedReader reader = new BufferedReader(new FileReader(kbFile));
			do
			{
				String line = reader.readLine();
				if (line != null)
					println(line);
				else
					break;
			} while (true);
			reader.close();
			println();
		}
		
		if (_outputTrans)
		{
			println("Translated KB:");
			println(transKB);
		}

		if (_engine.consultAbsolute(transKBFile))
		{
			println("KB Loaded");
			
			String path = transKBFile.getPath();
			path = path.substring(0, path.length() - 2).concat("xwam");			
			File xwamFile = new File(path);
			if (xwamFile.exists())
				xwamFile.deleteOnExit();
		}
		else
		{
			_engine.interrupt();
			println("Failed to load KB");
		}
		
		if (queryStream != null)
		{
			String transQuery = translator.translateQuery(queryStream);
			
			answerQuery(transQuery, translator);
		}
		else
		{
			BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
			String psoaQuery;
			
			do 
			{
				println("Input Query:");
				psoaQuery = reader.readLine();
				if (psoaQuery == null)
					break;
				
				try
				{
					String transQuery = translator.translateQuery(psoaQuery);
					answerQuery(transQuery, translator);
				}
				catch (Exception e)
				{
					e.printStackTrace();
				}
				println();
			} while (true);
			
			reader.close();
		}
		
		if (_engine != null)
			_engine.shutdown();
	}

	private static void answerQuery(String transQuery, PrologTranslator translator)
	{
		Set<Entry<String, String>> varMapEntries;
		TermModel result;
		
		if (_outputTrans)
		{
			println("Translated Query:");
			println(transQuery + ".");
			println();
		}
		varMapEntries = translator.getQueryVarMap().entrySet();
		
		println("Answer(s):");
		if (varMapEntries.isEmpty())
		{	
			println(_engine.deterministicGoal(transQuery)? "Yes" : "No");
		}
		else if (_getAllAnswers)
		{
			StringBuilder outputBuilder = new StringBuilder("findall([");
			for (Entry<String, String> entry : varMapEntries)
			{
				outputBuilder.append("\'?").append(entry.getValue()).append("=\',");
				outputBuilder.append(entry.getKey()).append(",");
			}
			outputBuilder.setCharAt(outputBuilder.length() - 1, ']');
			outputBuilder.append(",(").append(transQuery).append("),AS),buildTermModel(AS,LM)");
			
			result = (TermModel)_engine.deterministicGoal(outputBuilder.toString(), "[LM]")[0];
//			result = engine.deterministicGoal("findall([Q1],member(lo1,Q1),AS),buildTermModel(AS,LM)", "[LM]")[0];
			
			if (result.getChildCount() > 0)
			{
				Set<String> answers = new HashSet<String>();
				StringBuilder ansBuilder = new StringBuilder();
				boolean separator = false;
				for (TermModel bindings : result.flatList())
				{					
					for (TermModel term : bindings.flatList())
					{
						ansBuilder.append(translator.inverseTranslateTerm(term.toString()));
						if (separator)
							ansBuilder.append(",");
						separator = !separator;
					}
					ansBuilder.setLength(ansBuilder.length() - 1);
					
					String ans = ansBuilder.toString();
					if (answers.add(ans))
						println(ans);
					ansBuilder.setLength(0);
				}
			}
			println();
		}
		else
		{
			StringBuilder queryBuilder = new StringBuilder(transQuery);
			queryBuilder.append(",buildTermModel([");
			for (Entry<String, String> entry : varMapEntries)
			{
				queryBuilder.append("\'?").append(entry.getValue()).append("=\',");
				queryBuilder.append(entry.getKey()).append(",");
			}
			queryBuilder.setCharAt(queryBuilder.length() - 1, ']');
			queryBuilder.append(",LM)");

			String input = ";";
			Scanner sc = new Scanner(System.in);
			SolutionIterator iter = _engine.goal(queryBuilder.toString(), "[LM]");
			
			do
			{
				if (input.equals(";"))
				{
					if (!iter.hasNext())
					{
						System.out.println("No");
						break;
					}
					TermModel m = (TermModel)iter.next()[0];
					
					StringBuilder ansBuilder = new StringBuilder();
					boolean separator = false;
					for (TermModel term : m.flatList())
					{
						ansBuilder.append(translator.inverseTranslateTerm(term.toString()));
						if (separator)
							ansBuilder.append(",");
						separator = !separator;
					}
					ansBuilder.setCharAt(ansBuilder.length() - 1, '\t');
					
					System.out.print(ansBuilder);
				}
				else if (input.equals(""))
				{
					iter.cancel();
					break;
				}
				
				input = sc.nextLine();
			} while (true);
		}
	}
	
	private static void printUsage()
	{
		println("Usage: java -jar PSOATransRun.jar -i <kb> [-e] [-p] [-o <translated KB output>] [-q <query>] [-a] [-s] [-x <xsb folder>]");
		println("Options:");
		println("  -?,--help         Print the help message");
//		println("");
		println("  -a,--allAns       Retrieve all answers for each query at once");
		println("  -i,--input        Input Knowledge Base (KB)");
		println("  -e,--echoInput    Echo input KB to standard output");
		println("  -q,--query        Query document for the KB. If the query document");
		println("                    is not specified, the engine will read queries");
		println("                    from the standard input.");
		println("  -p,--printTrans   Print translated KB and queries to standard output");
		println("  -o,--outputTrans  Save translated KB to the designated file");
		println("  -x,--xsbfolder    Specifies XSB installation folder. The default path is ");
		println("                    obtained from the environment variable XSB_DIR");
		println("  -s,--staticOnly   Apply static objectification only");
	} // End printUsage()
}