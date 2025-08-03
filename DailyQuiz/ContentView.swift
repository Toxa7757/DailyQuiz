
//
//  ContentView.swift
//  DailyQuiz
//
//  Created by Тоха on 01.08.2025.
//

import SwiftUI
import Foundation

extension Color {
    static let customBackground = Color(red: 0.44, green: 0.42, blue: 1.0)
    static let answerBlockColor = Color(red: 0.73, green: 0.73, blue: 0.73)
    static let selectedAnswerColor = Color(red: 0.17, green: 0.0, blue: 0.39)
    static let scoreColor = Color(red: 0.737, green: 0.718, blue: 1.0)
    static let recordColor = Color(red: 1.0, green: 0.722, blue: 0.0)
    static let correctColor = Color(red: 0.0, green: 0.682, blue: 0.227)
    static let incorrectColor = Color(red: 0.906, green: 0.0, blue: 0.0)
}

struct Question: Decodable, Identifiable {
    var id: UUID = UUID()
    let category: String
    let type: String
    let difficulty: String
    let question: String
    let correct_answer: String
    let incorrect_answers: [String]

    enum CodingKeys: String, CodingKey {
        case category, type, difficulty, question, correct_answer, incorrect_answers
    }
}

struct TriviaResponse: Decodable {
    let results: [Question]
}

enum AppState {
    case main
    case loading
    case quiz
    case results
    case history
    case historyDetail(QuizResult) // Добавлено состояние для детального просмотра истории
    case error
}

// Добавлена информация об ответах пользователя на каждый вопрос
struct QuizResult: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let score: Int
    let totalQuestions: Int
    let attemptNumber: Int
    let questionResults: [QuestionResult] // Массив результатов по каждому вопросу
}

// Структура для хранения результата ответа на один вопрос
struct QuestionResult: Identifiable, Codable {
    let id = UUID()
    let question: String
    let correctAnswer: String
    let selectedAnswer: String? // nil, если вопрос не был отвечен
}

class QuizManager: ObservableObject {
    @Published var questions: [Question] = []
    @Published var currentQuestionIndex = 0
    @Published var selectedAnswer: String? = nil
    @Published var isAnswered: Bool = false
    @Published var quizFinished = false
    @Published var score = 0

    @Published var quizHistory: [QuizResult] = []
    private let historyKey = "quizHistory"
    private var attemptCounter = 0

    init() {
        loadHistory()
        attemptCounter = quizHistory.count + 1
    }

    @MainActor
    func loadQuestions() async throws {
        let loadedQuestions = try await getTriviaQuestions()
        questions = loadedQuestions.map { question in
            Question(
                category: question.category.decodingHTMLEntities(),
                type: question.type,
                difficulty: question.difficulty,
                question: question.question.decodingHTMLEntities(),
                correct_answer: question.correct_answer.decodingHTMLEntities(),
                incorrect_answers: question.incorrect_answers.map { $0.decodingHTMLEntities() }
            )
        }
        currentQuestionIndex = 0
        selectedAnswer = nil
        isAnswered = false
        quizFinished = false
        score = 0
    }

    func selectAnswer(_ answer: String) {
        selectedAnswer = answer
    }

    func confirmAnswer() {
        isAnswered = true
        if selectedAnswer == questions[currentQuestionIndex].correct_answer {
            score += 1
        }
    }

    func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
            isAnswered = false
        } else {
            quizFinished = true
        }
    }

    func resetQuiz() {
        currentQuestionIndex = 0
        selectedAnswer = nil
        isAnswered = false
        quizFinished = false
        score = 0
    }

    func getShuffledAnswers() -> [String] {
        var answers = questions[currentQuestionIndex].incorrect_answers
        answers.append(questions[currentQuestionIndex].correct_answer)
        return answers.shuffled()
    }

    func isCorrect(_ answer: String) -> Bool {
        return answer == questions[currentQuestionIndex].correct_answer
    }

    // Сохранение результатов викторины с информацией об ответах
    func saveResult() {
        var questionResults: [QuestionResult] = []
        for i in 0..<questions.count {
            let question = questions[i].question
            let correctAnswer = questions[i].correct_answer
            //Предполагается, что ответы сохраняются в том же порядке, что и вопросы.
            let selectedAnswer = savedAnswers[i]
            let questionResult = QuestionResult(question: question, correctAnswer: correctAnswer, selectedAnswer: selectedAnswer)
            questionResults.append(questionResult)
        }

        let result = QuizResult(date: Date(), score: score, totalQuestions: questions.count, attemptNumber: attemptCounter, questionResults: questionResults)
        quizHistory.append(result)
        saveHistory()
        attemptCounter += 1
        savedAnswers.removeAll()
    }
    @Published var savedAnswers: [String?] = []

    // Функция для сохранения ответа на текущий вопрос
    func saveCurrentAnswer() {
        savedAnswers.append(selectedAnswer)
    }

    internal func saveHistory() {
        if let encodedData = try? JSONEncoder().encode(quizHistory) {
            UserDefaults.standard.set(encodedData, forKey: historyKey)
        }
    }

    private func loadHistory() {
        if let savedData = UserDefaults.standard.data(forKey: historyKey),
           let decodedData = try? JSONDecoder().decode([QuizResult].self, from: savedData) {
            quizHistory = decodedData
        }
    }
}

struct ContentView: View {
    @State private var appState: AppState = .main
    @StateObject private var quizManager = QuizManager()

    var body: some View {
        switch appState {
        case .main:
            MainView(startQuiz: {
                startQuiz()
            }, showHistory: {
                appState = .history
            })
        case .loading:
            LoadingView()
        case .quiz:
            QuizView(quizManager: quizManager, quizFinished: {
                quizManager.saveResult()
                appState = .results
            }, saveCurrentAnswer: {
                quizManager.saveCurrentAnswer()
            })
        case .results:
            ResultsView(score: quizManager.score, totalQuestions: quizManager.questions.count, restartQuiz: {
                appState = .main
            })
        case .history:
            HistoryView(quizHistory: quizManager.quizHistory, backToMain: {
                appState = .main
            }, showHistoryDetail: { result in
                appState = .historyDetail(result)
            }, deleteHistoryEntry: { result in
                quizManager.quizHistory.removeAll { $0.id == result.id }
                quizManager.saveHistory()
                // Force update the view
                appState = .history
            })
        case .historyDetail(let result):
            HistoryDetailView(quizResult: result, backToHistory: {
                appState = .history
            })
        case .error:
            ErrorView(onRetry: {
                startQuiz()
            })
        }
    }

    func startQuiz() {
        appState = .loading
        Task {
            do {
                try await quizManager.loadQuestions()
                appState = .quiz
            } catch {
                print("Error loading questions: \(error)")
                appState = .error
            }
        }
    }
}

struct MainView: View {
    var startQuiz: () -> Void
    var showHistory: () -> Void
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.customBackground
                .edgesIgnoringSafeArea(.all)
            VStack {
                Image("LogoDQ")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
                    .padding(.bottom)

                VStack {
                    Text("Добро пожаловать в DailyQuiz!")
                        .foregroundColor(.black)
                        .fontWeight(.bold)
                        .padding()
                        .font(.system(size: 30))
                        .multilineTextAlignment(.center)

                    Button(action: {
                        startQuiz()
                    }) {
                        Text("НАЧАТЬ ВИКТОРИНУ")
                    }
                    .padding()
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.horizontal)
                    .background(Color.customBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom)

                    Button(action: {
                        showHistory()
                    }) {
                        Text("ИСТОРИЯ ВИКТОРИН")
                    }
                    .padding()
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.horizontal)
                    .background(Color.scoreColor)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom)
                    .padding(.bottom)

                    if showError {
                        Text("Ошибка! Попробуйте ещё раз.")
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 40))
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.customBackground.edgesIgnoringSafeArea(.all)
            VStack {
                Image("LogoDQ")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
                    .padding(.bottom)
                    .padding(.bottom)
                ProgressView()
                    .scaleEffect(2.0, anchor: .center)
                    .padding()
            }
        }
    }
}

struct QuizView: View {
    @ObservedObject var quizManager: QuizManager
    var quizFinished: () -> Void
    var saveCurrentAnswer: () -> Void

    var body: some View {
        ZStack {
            Color.customBackground.edgesIgnoringSafeArea(.all)
            VStack {
                if quizManager.quizFinished {
                   EmptyView()
                } else if !quizManager.questions.isEmpty{
                    Image("LogoDQ")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300)
                        .padding(.bottom)
                        .padding(.bottom)
                    Text("Вопрос \(quizManager.currentQuestionIndex + 1) из \(quizManager.questions.count)")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .font(.headline)
                        .padding(.top)

                    QuestionCardView(question: quizManager.questions[quizManager.currentQuestionIndex], selectedAnswer: quizManager.selectedAnswer, isAnswered: quizManager.isAnswered, selectAnswer: { answer in
                        quizManager.selectAnswer(answer)
                    }, isCorrect: { answer in
                        quizManager.isCorrect(answer)
                    })
                    .padding()

                    Button(action: {
                        if !quizManager.isAnswered {
                            quizManager.confirmAnswer()
                            saveCurrentAnswer() // Сохраняем текущий ответ
                        } else {
                            if quizManager.currentQuestionIndex == quizManager.questions.count - 1 {
                                quizFinished()
                            } else {
                                quizManager.nextQuestion()
                            }
                        }
                    }) {
                        Text(quizManager.selectedAnswer == nil ? "ДАЛЕЕ" : (!quizManager.isAnswered ? "ДАЛЕЕ" : (quizManager.currentQuestionIndex == quizManager.questions.count - 1 ? "ЗАВЕРШИТЬ" : "ДАЛЕЕ")))
                            .padding()
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                            .background(quizManager.selectedAnswer == nil ? Color.answerBlockColor : Color.selectedAnswerColor)
                            .cornerRadius(10)
                    }
                    .disabled(quizManager.selectedAnswer == nil)
                    .padding(.bottom)
                    Text("Вернуться к предыдущим вопросом нельзя")
                        .foregroundColor(.white)

                } else {
                    Text("Ошибка загрузки...")
                        .foregroundColor(.white)
                        .font(.title)
                        .padding()
                }
            }
        }
    }
}

struct QuestionCardView: View {
    let question: Question
    let selectedAnswer: String?
    let isAnswered: Bool
    let selectAnswer: (String) -> Void
    let isCorrect: (String) -> Bool

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(.white)
                .overlay(
                    VStack {
                        Text(question.question)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        ForEach(question.incorrect_answers + [question.correct_answer], id: \.self) { answer in
                            AnswerBlockView(answer: answer, isSelected: selectedAnswer == answer, isAnswered: isAnswered, isCorrect: isCorrect(answer), selectAnswer: selectAnswer)
                        }
                    }
                        .padding(.horizontal)
                )
        }
    }
}

struct AnswerBlockView: View {
    let answer: String
    let isSelected: Bool
    let isAnswered: Bool
    let isCorrect: Bool
    let selectAnswer: (String) -> Void

    var body: some View {
        Button(action: {
            if !isAnswered {
                selectAnswer(answer)
            }
        }) {
            HStack {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundColor(isAnswered ? (isCorrect ? Color.correctColor : Color.incorrectColor) : Color.selectedAnswerColor)
                        .padding()
                } else {
                    Image(systemName: "circle")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundColor(Color.selectedAnswerColor)
                        .padding()
                }
                Text(answer)
                    .foregroundColor(.black)
                    .padding()
                Spacer()

            }
            .background(
                (isSelected && isAnswered) ? (isCorrect ? Color.correctColor.opacity(0.3) : Color.incorrectColor.opacity(0.3)) : Color.clear
            )
            .cornerRadius(10)
        }
        .disabled(isAnswered)
    }
}

struct ResultsView: View {
    let score: Int
    let totalQuestions: Int
    let restartQuiz: () -> Void

    var body: some View {
        VStack {
            Text("Результаты")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.bottom)

            VStack {
                switch score {
                case 0:
                    Image("0stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 70)
                    Text("0 из 5")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.vertical)
                    Text("Бывает и так!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("0/5 — не отчаивайтесь. Начните заново и удивите себя!")
                        .padding(.bottom)
                case 1:
                    Image("1stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 70)
                    Text("1 из 5")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.vertical)
                    Text("Сложный вопрос?")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("1/5 — иногда просто не ваш день. Следующая попытка будет лучше!")
                        .padding(.bottom)
                case 2:
                    Image("2stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 70)
                    Text("2 из 5")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.vertical)
                    Text("Есть над чем поработать")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("2/5 — не расстраивайтесь, попробуйте ещё раз!")
                        .padding(.bottom)
                case 3:
                    Image("3stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 70)
                    Text("3 из 5")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.vertical)
                    Text("Хороший результат!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("3/5 — вы на верном пути. Продолжайте тренироваться!")
                        .padding(.bottom)
                case 4:
                    Image("4stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 70)
                    Text("4 из 5")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.vertical)
                    Text("Почти идеально")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("4/5 — очень близко к совершенству. Ещё один шаг!")
                        .padding(.bottom)
                case 5:
                    Image("5stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 70)
                    Text("5 из 5")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.vertical)
                    Text("Идеально!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("5/5 — вы ответили на всё правильно. Это блестящий результат!")
                        .padding(.bottom)
                default:
                    Text("Неожиданный результат!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Что-то пошло не так")
                        .padding(.bottom)
                }

                Button("НА ГЛАВНУЮ") {
                    restartQuiz()
                }
                .padding()
                .padding(.horizontal)
                .padding(.horizontal)
                .fontWeight(.bold)
                .background(Color.customBackground)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .padding(.vertical)
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 50))
        }
        .padding(.bottom)
        .background(Color.customBackground)
    }
}

struct HistoryView: View {
    let quizHistory: [QuizResult]
    var backToMain: () -> Void
    var showHistoryDetail: (QuizResult) -> Void
    var deleteHistoryEntry: (QuizResult) -> Void

    @State private var showDeleteConfirmation: Bool = false
    @State private var selectedQuizResult: QuizResult? = nil

    var body: some View {
        ZStack {
            Color.customBackground.edgesIgnoringSafeArea(.all)
            VStack {
                Text("История")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top)

                if quizHistory.isEmpty {
                    Text("Вы ещё не проходили ни одной викторины")
                        .foregroundColor(.black)
                        .padding()
                        .padding(.horizontal)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 40))
                } else {
                    ScrollView {
                        VStack {
                            ForEach(quizHistory) { result in
                                HistoryEntryView(quizResult: result, showHistoryDetail: showHistoryDetail, confirmDelete: { quizResult in
                                    selectedQuizResult = quizResult
                                    showDeleteConfirmation = true
                                })
                                .padding(.horizontal)
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }

                Button("На главную") {
                    backToMain()
                }
                .padding()
                .background(Color.selectedAnswerColor)
                .foregroundColor(.white)
                .fontWeight(.bold)
                .clipShape(RoundedRectangle(cornerRadius: 40))
                .padding(.bottom)
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Удалить попытку?"),
                message: Text("Вы уверены, что хотите удалить эту попытку из истории?"),
                primaryButton: .destructive(Text("Удалить"), action: {
                    if let result = selectedQuizResult {
                        deleteHistoryEntry(result)
                    }
                    selectedQuizResult = nil
                }),
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
    }
}

struct HistoryEntryView: View {
    let quizResult: QuizResult
    let showHistoryDetail: (QuizResult) -> Void
    let confirmDelete: (QuizResult) -> Void

    var body: some View {
        Button(action: {
            showHistoryDetail(quizResult)
        }) {
            VStack(alignment: .leading) {
                HStack {
                    Text("  Quiz \(quizResult.attemptNumber)")
                        .font(.headline)
                        .foregroundColor(.selectedAnswerColor)
                        .fontWeight(.bold)
                        .font(.largeTitle)
                    Spacer()
                    /*Text(formattedDate(quizResult.date))
                        .font(.subheadline)
                        .foregroundColor(.gray) */
                    Image(String(quizResult.score)+"stars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 50)
                    
                }
                HStack {
                    Spacer()
                    Text(formattedDate(quizResult.date))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    Spacer()
                    /*
                    Text("Результат:")
                        .font(.subheadline)
                        .foregroundColor(.black)
                    Text("\(quizResult.score) / \(quizResult.totalQuestions)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor) */
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(40)
        }
        .buttonStyle(PlainButtonStyle()) // Убираем стандартный стиль кнопки

        .overlay(alignment: .topTrailing) {
                Button(action: {
                    confirmDelete(quizResult)
                }) {
                    Image(systemName: "eraser")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            .offset(x: 10, y: -10) // Adjust the position as needed
        }
        .padding(.bottom, 5)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct HistoryDetailView: View {
    let quizResult: QuizResult
    var backToHistory: () -> Void

    var body: some View {
        ZStack(alignment: .center) {
            Color.customBackground.edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(alignment: .center) {
                    Text("Результаты Quiz \(quizResult.attemptNumber)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top)
                    /* Text("Дата: \(formattedDate(quizResult.date))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom) */
                    /* Text("Результат: \(quizResult.score) / \(quizResult.totalQuestions)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.recordColor)
                        .padding(.bottom) */
                    VStack{
                        
                        switch quizResult.score {
                        case 0:
                            Image("0stars")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 300, height: 70)
                            Text("0 из 5")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.recordColor)
                                .padding(.vertical)
                            Text("Бывает и так!")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("0/5 — не отчаивайтесь. Начните заново и удивите себя!")
                                .padding(.bottom)
                        case 1:
                            Image("1stars")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 300, height: 70)
                            Text("1 из 5")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.recordColor)
                                .padding(.vertical)
                            Text("Сложный вопрос?")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("1/5 — иногда просто не ваш день. Следующая попытка будет лучше!")
                                .padding(.bottom)
                        case 2:
                            Image("2stars")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 300, height: 70)
                            Text("2 из 5")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.recordColor)
                                .padding(.vertical)
                            Text("Есть над чем поработать")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("2/5 — не расстраивайтесь, попробуйте ещё раз!")
                                .padding(.bottom)
                        case 3:
                            Image("3stars")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 300, height: 70)
                            Text("3 из 5")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.recordColor)
                                .padding(.vertical)
                            Text("Хороший результат!")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("3/5 — вы на верном пути. Продолжайте тренироваться!")
                                .padding(.bottom)
                        case 4:
                            Image("4stars")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 300, height: 70)
                            Text("4 из 5")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.recordColor)
                                .padding(.vertical)
                            Text("Почти идеально")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("4/5 — очень близко к совершенству. Ещё один шаг!")
                                .padding(.bottom)
                        case 5:
                            Image("5stars")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 300, height: 70)
                            Text("5 из 5")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.recordColor)
                                .padding(.vertical)
                            Text("Идеально!")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("5/5 — вы ответили на всё правильно. Это блестящий результат!")
                                .padding(.bottom)
                        default:
                            Text("Неожиданный результат!")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("Что-то пошло не так")
                                .padding(.bottom)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(40)
                    Text("Твои ответы")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.bottom)
                    

                    ForEach(quizResult.questionResults) { questionResult in
                        VStack(alignment: .center) {
                                if questionResult.selectedAnswer == questionResult.correctAnswer {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.correctColor)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.incorrectColor)
                                }
                            Text("\(questionResult.question)")
                                //.font(.headline)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            Text("Правильный ответ: \(questionResult.correctAnswer)")
                                .foregroundColor(.gray)
                                .padding()
                                .fontWeight(.bold)
                            Text("Ваш ответ: \(questionResult.selectedAnswer ?? "Не отвечено")")
                                .fontWeight(.bold)
                                .foregroundColor(questionResult.selectedAnswer == questionResult.correctAnswer ? .green : .red)
                                .padding(.bottom, 5)
                            
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(40)
                    }

                    Button("Назад к истории") {
                        backToHistory()
                    }
                    .padding()
                    .fontWeight(.bold)
                    .background(Color.selectedAnswerColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 40))
                    .padding(.top)
                }
                .padding()
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ErrorView: View {
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.customBackground.edgesIgnoringSafeArea(.all)
            VStack {
                Text("Произошла ошибка при загрузке вопросов.")
                    .foregroundColor(.white)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Повторить попытку") {
                    onRetry()
                }
                .padding()
                .background(Color.white)
                .foregroundColor(.customBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

func getTriviaQuestions(amount: Int = 5, category: Int = 9, difficulty: String = "easy") async throws -> [Question] {
    let urlString = "https://opentdb.com/api.php?amount=\(amount)&category=\(category)&difficulty=\(difficulty)&type=multiple"

    guard let url = URL(string: urlString) else {
        throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
    }

    let (data, _) = try await URLSession.shared.data(from: url)

    let decodedResponse = try JSONDecoder().decode(TriviaResponse.self, from: data)
    return decodedResponse.results
}

#Preview {
    ContentView()
}

extension String {
    func decodingHTMLEntities() -> String {
        guard let data = self.data(using: .utf8) else {
            return self
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self
        }

        return attributedString.string
    }
}
