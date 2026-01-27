# Diver: Machine Learning & Intelligence Guide

## 1. Introduction: The "Hybrid Intelligence" Strategy

The Diver application employs a **Hybrid Intelligence** architecture. Rather than relying on a single large model for everything, it orchestrates three distinct layers of machine learning, each optimized for a specific cognitive task.

This approach ensures the app is:
1.  **Fast & Private**: Using on-device Core ML for visual perception.
2.  **Context-Aware**: Using Vector Embeddings (Know Maps) for long-term memory.
3.  **Human-Like**: Using Generative AI (Foundation Models) for synthesizing narrative.

---

## Layer 1: The "Eyes" (Perception)
**Technology**: Core ML & Compass (Vision Framework)

This layer is responsible for **Deterministic Perception**. It answers: *"What is literally in this image?"*

### Core Components
*   **Subject Sifting (`VNGenerateForegroundInstanceMaskRequest`)**: 
    *   This is the first step in the `IntelligenceProcessor`. It separates the signal (the subject) from the noise (the background).
    *   **Usage**: The system calculates a dynamic **Region of Interest (ROI)** based on the sifted subject. Subsequent expensive operations (like OCR) are focused *only* on this ROI, significantly improving accuracy and speed.
*   **Optical Character Recognition (OCR)**:
    *   Extracts text from menus, signs, and screens.
    *   **Heuristic**: Text found within the sifted subject bounds is prioritized over background text.
*   **Object Classification (`VNClassifyImageRequest`)**:
    *   Provides semantic labels (e.g., "Espresso Machine", "Receipt").
    *   These labels act as raw "keywords" for the next layer.

---

## Layer 2: The "Memory" (Association)
**Technology**: Know Maps Vector Space (BERT / MiniLM)

This layer is responsible for **Personalized Association**. It answers: *"Why does this matter to **this** user?"*

### The Vector Space
Diver integrates with **Know Maps**, a semantic knowledge graph that stores user data not just as text, but as **high-dimensional vectors** (embeddings).

*   **Model**: `MiniLMEmbeddingClient` (Use of a BERT-based Core ML model).
*   **Concept Storage**: When a user saves an item (e.g., a specific coffee shop), the system updates the weights of related concepts in the vector space (e.g., "Coffee", "Third Wave", "Work Friendly").

### How it is Used (`KnowMapsRetrievalAdapter`)
When a new image is captured, the system performs a **Retrieval Augmented Generation (RAG)** step:

1.  **Query**: The labels from Layer 1 (e.g., "Espresso") are sent to the Know Maps service.
2.  **Retrieval**: The service scans the vector space for the user's *Personalized Search Section*.
3.  **Context Injection**:
    *   If the user frequently saves "Gaming" content, and the image contains a "Laptop", the system retrieves the concept: *"User values High Performance Computing"*.
    *   This retrieved context is passed to Layer 3, effectively giving the AI "Long-Term Memory."

---

## Layer 3: The "Brain" (Cognition)
**Technology**: Apple Foundation Models (`SystemLanguageModel`)

This layer is responsible for **Generative Synthesis**. It answers: *"What is the story here?"*

### The Prompt Engineering Flow
The `ContextQuestionService` acts as the orchestrator. It constructs a rich prompt by combining signals from all previous layers:

```text
CONTEXT:
[Vision]: "Latte", "Laptop", "Rainy Window"
[Location]: "Starbucks, 5th Ave"
[Memory]: "User likes 'Remote Work' and 'Cozy Vibes'" (Retrieved from Know Maps)

TASK:
Summarize the user's intent.
```

### Key Capabilities
*   **Intent Detection**: The model can infer that "Laptop + Coffee" implies "Working Remotely," whereas "Coffee + Bagel" implies "Breakfast."
*   **Hallucination Control**: The system uses strict logical guardrails. For example, it explicitly forbids the model from guessing the location is "Home" unless there is GPS evidence, preventing false data pollution.
*   **Tag Generation**: It automatically generates semantic tags (e.g., `#WorkMode`, `#RainyDay`) that function as hooks for future vector retrieval.

---

## Summary of Data Flow

| Stage | Input | ML Model | Output |
| :--- | :--- | :--- | :--- |
| **1. Capture** | Raw Pixel Buffer | **Vision (Core ML)** | Sifted Image, Text: "Latte", Label: "Coffee" |
| **2. Recall** | Label: "Coffee" | **Know Maps (BERT)** | Concept: "User likes Remote Work" (Weight: 0.9) |
| **3. Enrich** | GPS Coords | **Foursquare API** | Venue: "Starbucks" |
| **4. Think** | "Latte" + "Remote Work" + "Starbucks" | **Foundation Model (LLM)** | Title: "Remote Work Session"<br>Intent: "Working" |

This architecture allows Diver to be far smarter than a simple "Photo Saver". It understands the *semantic relationship* between your content, your location, and your history, creating a true "Second Brain."
