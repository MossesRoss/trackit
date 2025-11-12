/**
 * @author Mosses
 * @version 1.1.0
 * @description 100% Free backend proxy for TrackIt Gemini API calls.
 * --- CHANGELOG ---
 * v1.1.0: Updated to use modern destructuring for response handling.
 * v1.0.0: Initial creation. Handles getSuggestion, getTaskSuggestions, 
 * and getMonthlyReportSummary via UrlFetchApp.
 */

/**
 * Main entry point for POST requests.
 */
function doPost(e) {
  let responseData;
  try {
    const body = JSON.parse(e.postData.contents);
    const { action } = body; // Use destructuring

    // Log the incoming request (using modern object logging)
    console.log("Received request:", { action, body });

    // Get the secure API key from Script Properties
    const GEMINI_API_KEY = PropertiesService.getScriptProperties().getProperty('GEMINI_API_KEY');

    if (!GEMINI_API_KEY) {
      console.error("CRITICAL ERROR: GEMINI_API_KEY is not set in Script Properties.");
      responseData = { error: "API_KEY_NOT_SET_ON_SERVER" };
      return createJsonOutput(responseData);
    }

    let prompt;
    switch (action) {
      case 'getSuggestion':
        prompt = body.prompt;
        responseData = callGeminiApi(prompt, false, GEMINI_API_KEY);
        break;

      case 'getTaskSuggestions':
        const { goalTitle, milestoneTitle } = body;
        prompt = `
          A user is planning their goal.
          Main Goal: "${goalTitle}"
          Current Milestone: "${milestoneTitle}"
          Suggest 3 to 4 actionable, specific sub-tasks for this milestone.
        `;
        responseData = callGeminiApi(prompt, true, GEMINI_API_KEY);
        break;

      case 'getMonthlyReportSummary':
        const { currentData, previousData } = body;
        // The data (e.g., timeSpent) is now just a number (seconds), which is perfect.
        prompt = `
          Generate a concise, encouraging, single-paragraph monthly performance report.
          Focus on positive reinforcement. Do not use markdown.
          Data:
          - This month's time (seconds): ${currentData['timeSpent']}
          - This month's tasks: ${currentData['tasksCompleted']}
          - Last month's time (seconds): ${previousData['timeSpent']}
          - Last month's tasks: ${previousData['tasksCompleted']}
        `;
        responseData = callGeminiApi(prompt, false, GEMINI_API_KEY);
        break;

      default:
        console.warn(`Unknown action: ${action}`);
        responseData = { error: 'Unknown action' };
        break;
    }
  } catch (err) {
    console.error(`Error in doPost: ${err.message}`, { stack: err.stack });
    responseData = { error: err.message };
  }
  
  return createJsonOutput(responseData);
}

/**
 * Reusable function to call the Google Gemini API.
 */
function callGeminiApi(prompt, isJson, apiKey) {
  const model = "gemini-2.5-flash-preview-09-2025";
  const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const generationConfig = isJson
    ? {
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: {
            tasks: {
              type: "ARRAY",
              items: { type: "STRING" },
            },
          },
        },
      }
    : undefined;

  const payload = {
    contents: [{
      role: "user",
      parts: [{ text: prompt }],
    }],
    ...(generationConfig && { generationConfig }), // Modern spread syntax
  };

  const options = {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true // IMPORTANT: This lets us catch non-200 errors
  };

  try {
    const response = UrlFetchApp.fetch(apiUrl, options);
    const responseCode = response.getResponseCode();
    const responseBody = response.getContentText();

    if (responseCode === 200) {
      const data = JSON.parse(responseBody);
      
      // Use modern destructuring to safely get the text
      const { candidates: [firstCandidate] = [] } = data;
      const text = firstCandidate?.content?.parts?.[0]?.text?.trim();

      if (text) {
        return { suggestion: text };
      } else {
        console.error("Gemini API Error: No valid candidate found in response.", { responseBody });
        return { error: "API_ERROR: No content generated." };
      }
    } else {
      console.error(`Gemini API Error (Code ${responseCode})`, { responseBody });
      return { error: `API_ERROR: ${responseCode}` };
    }
  } catch (e) {
    console.error(`Network Error: ${e.message}`, { stack: e.stack });
    return { error: "NETWORK_ERROR" };
  }
}

/**
 * Helper function to return a JSON ContentService object.
 */
function createJsonOutput(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}
